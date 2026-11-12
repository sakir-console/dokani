<?php

namespace App\Services\Inventory;

use App\Enums\StockMovementType;
use App\Exceptions\ApiException;
use App\Models\ProductVariant;
use App\Models\StockMovement;
use App\Models\User;
use App\Services\Tenancy\TenantContext;
use App\Support\Dec;
use Brick\Math\BigDecimal;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;

/**
 * The only place stock changes.
 *
 * Every change locks the variant row, updates the cached balance and writes
 * a stock_movements row with the resulting balance — in one transaction.
 * Two requests changing the same variant therefore run one after the other
 * and neither update is lost.
 */
class StockService
{
    /**
     * @param  array{unit_cost?: ?string, vendor_id?: ?int, note?: ?string, reference?: ?Model, allow_negative?: bool, include_deleted?: bool}  $options
     */
    public function change(int $variantId, StockMovementType $type, BigDecimal|string $signedQuantity, ?User $actor = null, array $options = []): StockMovement
    {
        return DB::transaction(function () use ($variantId, $type, $signedQuantity, $actor, $options) {
            /** @var ProductVariant|null $variant */
            // include_deleted: returning stock for a voided sale must work even if the product was deleted since.
            $variant = ProductVariant::query()
                ->when($options['include_deleted'] ?? false, fn ($q) => $q->withTrashed())
                ->with(['product' => fn ($q) => $q->withTrashed()->with('unit')])
                ->lockForUpdate()->find($variantId);

            if ($variant === null) {
                throw new ApiException('VARIANT_NOT_FOUND', __('The product was not found.'), 404);
            }

            $quantity = Dec::of($signedQuantity);

            if (! $variant->product->unit->allows_decimal && ! Dec::isWhole($quantity)) {
                throw new ApiException('QUANTITY_MUST_BE_WHOLE', __('This product is counted in whole units.'), 422, [
                    'quantity' => [__('This product is counted in whole units.')],
                ]);
            }

            $balance = Dec::of($variant->stock_quantity)->plus($quantity);

            $allowNegative = ($options['allow_negative'] ?? false)
                || (bool) app(TenantContext::class)->shop()->resolvedSettings()['allow_negative_stock'];

            if ($balance->isNegative() && $quantity->isNegative() && ! $allowNegative) {
                throw ApiException::conflict('INSUFFICIENT_STOCK', __('Not enough stock. Available: :available', [
                    'available' => rtrim(rtrim(Dec::qty($variant->stock_quantity), '0'), '.'),
                ]));
            }

            // Not mass-assignable on purpose; this is the one writer.
            $variant->stock_quantity = Dec::qty($balance);
            $variant->save();

            $movement = new StockMovement([
                'type' => $type,
                'quantity' => Dec::qty($quantity),
                'balance_after' => Dec::qty($balance),
                'unit_cost' => isset($options['unit_cost']) ? Dec::money($options['unit_cost']) : null,
                'vendor_id' => $options['vendor_id'] ?? null,
                'note' => $options['note'] ?? null,
                'created_by' => $actor?->id,
            ]);
            $movement->product_variant_id = $variant->id;

            if (($reference = $options['reference'] ?? null) instanceof Model) {
                $movement->reference_type = $reference->getMorphClass();
                $movement->reference_id = $reference->getKey();
            }

            $movement->save();

            return $movement;
        });
    }

    /** Goods received. Optionally records the cost paid and updates the variant's current cost. */
    public function stockIn(int $variantId, string $quantity, ?User $actor, ?string $unitCost = null, ?int $vendorId = null, ?string $note = null): StockMovement
    {
        return DB::transaction(function () use ($variantId, $quantity, $actor, $unitCost, $vendorId, $note) {
            $movement = $this->change($variantId, StockMovementType::StockIn, Dec::of($quantity), $actor, [
                'unit_cost' => $unitCost, 'vendor_id' => $vendorId, 'note' => $note,
            ]);

            if ($unitCost !== null) {
                // Latest cost becomes the current cost. Past sales keep the cost they were sold at.
                ProductVariant::query()->whereKey($variantId)->update(['purchase_price' => Dec::money($unitCost)]);
            }

            return $movement;
        });
    }

    /** Goods removed for a reason other than a sale: damaged, expired, own use. */
    public function stockOut(int $variantId, string $quantity, ?User $actor, string $note): StockMovement
    {
        return $this->change($variantId, StockMovementType::StockOut, Dec::of($quantity)->negated(), $actor, ['note' => $note]);
    }

    /**
     * Set stock to the quantity actually counted. Records the difference.
     * Returns null when the count matches what the system already has.
     */
    public function adjustTo(int $variantId, string $countedQuantity, ?User $actor, ?string $note = null): ?StockMovement
    {
        return DB::transaction(function () use ($variantId, $countedQuantity, $actor, $note) {
            $current = ProductVariant::query()->whereKey($variantId)->lockForUpdate()->value('stock_quantity');

            if ($current === null) {
                throw new ApiException('VARIANT_NOT_FOUND', __('The product was not found.'), 404);
            }

            $difference = Dec::of($countedQuantity)->minus(Dec::of($current));

            if ($difference->isZero()) {
                return null;
            }

            // A count can legitimately correct a negative balance in either direction.
            return $this->change($variantId, StockMovementType::Adjustment, $difference, $actor, ['note' => $note, 'allow_negative' => true]);
        });
    }
}
