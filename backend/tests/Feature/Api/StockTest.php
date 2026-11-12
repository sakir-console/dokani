<?php

namespace Tests\Feature\Api;

use App\Models\ProductVariant;
use App\Models\StockMovement;
use App\Models\Vendor;
use Tests\TestCase;

class StockTest extends TestCase
{
    private function stockOf(int $variantId): string
    {
        return $this->tenant()->withoutTenancy(fn () => ProductVariant::query()->whereKey($variantId)->value('stock_quantity'));
    }

    public function test_stock_in_adds_stock_records_the_movement_and_updates_the_cost(): void
    {
        $shop = $this->createShop();
        $this->subscribe($shop, 'basic');
        $variant = $this->createProduct($shop)->variants[0];
        $vendor = $this->tenant()->runFor($shop, fn () => Vendor::factory()->create());

        $this->asOwnerOf($shop)->postJson('/api/v1/stock/in', [
            'variant_id' => $variant->id, 'quantity' => '15', 'unit_cost' => '55.25', 'vendor_id' => $vendor->id, 'note' => 'Weekly delivery',
        ])->assertCreated()
            ->assertJsonPath('data.type', 'stock_in')
            ->assertJsonPath('data.quantity', '15.000')
            ->assertJsonPath('data.balance_after', '25.000')
            ->assertJsonPath('data.unit_cost', '55.25')
            ->assertJsonPath('data.vendor.id', $vendor->id);

        $this->assertSame('25.000', $this->stockOf($variant->id));
        // The latest cost becomes the current purchase price.
        $this->asOwnerOf($shop)->getJson("/api/v1/products/{$variant->product_id}")
            ->assertJsonPath('data.variants.0.purchase_price', '55.25');

        // It shows up as a purchase from that vendor.
        $this->asOwnerOf($shop)->getJson("/api/v1/vendors/{$vendor->id}/purchases")->assertOk()
            ->assertJsonCount(1, 'data')->assertJsonPath('data.0.quantity', '15.000');
    }

    public function test_stock_in_without_a_cost_leaves_the_purchase_price_alone(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop)->variants[0];

        $this->asOwnerOf($shop)->postJson('/api/v1/stock/in', ['variant_id' => $variant->id, 'quantity' => 1])->assertCreated();

        $this->asOwnerOf($shop)->getJson("/api/v1/products/{$variant->product_id}")
            ->assertJsonPath('data.variants.0.purchase_price', '50.00');
    }

    public function test_stock_out_needs_a_reason_and_cannot_exceed_what_is_there(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop)->variants[0];
        $out = fn (array $data) => $this->asOwnerOf($shop)->postJson('/api/v1/stock/out', ['variant_id' => $variant->id] + $data);

        $out(['quantity' => 2])->assertUnprocessable()->assertJsonValidationErrors('note');
        $out(['quantity' => 0, 'note' => 'x'])->assertUnprocessable()->assertJsonValidationErrors('quantity');
        $out(['quantity' => -3, 'note' => 'x'])->assertUnprocessable()->assertJsonValidationErrors('quantity');

        $out(['quantity' => 11, 'note' => 'Damaged'])->assertConflict()->assertJsonPath('code', 'INSUFFICIENT_STOCK');
        $this->assertSame('10.000', $this->stockOf($variant->id));

        $out(['quantity' => 4, 'note' => 'Damaged'])->assertCreated()
            ->assertJsonPath('data.type', 'stock_out')
            ->assertJsonPath('data.quantity', '-4.000')
            ->assertJsonPath('data.balance_after', '6.000');
        $this->assertSame('6.000', $this->stockOf($variant->id));
    }

    public function test_a_shop_that_allows_negative_stock_can_go_below_zero(): void
    {
        $shop = $this->createShop(['settings' => ['allow_negative_stock' => true]]);
        $variant = $this->createProduct($shop)->variants[0];

        $this->asOwnerOf($shop)->postJson('/api/v1/stock/out', ['variant_id' => $variant->id, 'quantity' => 12, 'note' => 'Gift'])
            ->assertCreated()->assertJsonPath('data.balance_after', '-2.000');
    }

    public function test_adjusting_sets_the_counted_quantity_and_records_the_difference(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop)->variants[0];
        $adjust = fn ($quantity) => $this->asOwnerOf($shop)->postJson('/api/v1/stock/adjust', [
            'variant_id' => $variant->id, 'new_quantity' => $quantity, 'note' => 'Stock count',
        ]);

        $adjust(7)->assertCreated()
            ->assertJsonPath('data.type', 'adjustment')
            ->assertJsonPath('data.quantity', '-3.000')
            ->assertJsonPath('data.balance_after', '7.000');

        $adjust(7)->assertOk()->assertJsonPath('data', null)->assertJsonPath('meta.changed', false);
        $adjust(12)->assertCreated()->assertJsonPath('data.quantity', '5.000');
        $adjust(-1)->assertUnprocessable();

        $this->assertSame('12.000', $this->stockOf($variant->id));
        // opening + two real adjustments; the no-op left no row.
        $this->tenant()->runFor($shop, fn () => $this->assertSame(3, StockMovement::query()->count()));
    }

    public function test_fractional_quantities_follow_the_products_unit(): void
    {
        $shop = $this->createShop();
        $rice = $this->createProduct($shop, ['unit_id' => $this->unitId('Kilogram')])->variants[0];
        $soap = $this->createProduct($shop)->variants[0];

        $this->asOwnerOf($shop)->postJson('/api/v1/stock/in', ['variant_id' => $rice->id, 'quantity' => '0.250'])
            ->assertCreated()->assertJsonPath('data.balance_after', '10.250');

        $this->asOwnerOf($shop)->postJson('/api/v1/stock/in', ['variant_id' => $soap->id, 'quantity' => '0.5'])
            ->assertUnprocessable()->assertJsonPath('code', 'QUANTITY_MUST_BE_WHOLE');
        $this->asOwnerOf($shop)->postJson('/api/v1/stock/in', ['variant_id' => $rice->id, 'quantity' => '0.0001'])
            ->assertUnprocessable()->assertJsonValidationErrors('quantity');
    }

    public function test_every_movement_carries_the_running_balance(): void
    {
        $shop = $this->createShop();
        $this->subscribe($shop, 'basic');
        $variant = $this->createProduct($shop)->variants[0];

        $this->asOwnerOf($shop)->postJson('/api/v1/stock/in', ['variant_id' => $variant->id, 'quantity' => 5])->assertCreated();
        $this->asOwnerOf($shop)->postJson('/api/v1/stock/out', ['variant_id' => $variant->id, 'quantity' => 8, 'note' => 'Expired'])->assertCreated();
        $this->asOwnerOf($shop)->postJson('/api/v1/stock/adjust', ['variant_id' => $variant->id, 'new_quantity' => 20])->assertCreated();

        $history = $this->asOwnerOf($shop)->getJson('/api/v1/stock/movements?variant_id='.$variant->id)->assertOk()->json('data');

        $this->assertSame(['adjustment', 'stock_out', 'stock_in', 'opening'], array_column($history, 'type'));
        $this->assertSame(['20.000', '7.000', '15.000', '10.000'], array_column($history, 'balance_after'));

        // The history always adds up to the current stock.
        $sum = array_sum(array_map('floatval', array_column($history, 'quantity')));
        $this->assertSame(20.0, $sum);
        $this->assertSame('20.000', $this->stockOf($variant->id));

        $this->asOwnerOf($shop)->getJson('/api/v1/stock/movements?type=stock_out')->assertJsonCount(1, 'data');
    }

    public function test_the_movement_history_needs_the_inventory_module_but_stock_changes_do_not(): void
    {
        $shop = $this->createShop(); // free plan
        $variant = $this->createProduct($shop)->variants[0];

        $this->asOwnerOf($shop)->postJson('/api/v1/stock/in', ['variant_id' => $variant->id, 'quantity' => 1])->assertCreated();
        $this->asOwnerOf($shop)->getJson('/api/v1/stock/movements')->assertForbidden()->assertJsonPath('code', 'MODULE_NOT_AVAILABLE');
    }

    public function test_movements_cannot_be_edited_or_deleted(): void
    {
        $shop = $this->createShop();
        $this->createProduct($shop);

        $this->tenant()->runFor($shop, function () {
            $movement = StockMovement::query()->firstOrFail();

            try {
                $movement->update(['quantity' => '999']);
                $this->fail('A stock movement was updated.');
            } catch (\LogicException) {
            }

            $this->expectException(\LogicException::class);
            $movement->delete();
        });
    }
}
