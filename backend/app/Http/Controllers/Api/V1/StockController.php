<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\StockMovementType;
use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\StockRequest;
use App\Http\Resources\StockMovementResource;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\StockMovement;
use App\Services\Inventory\StockService;
use App\Services\Tenancy\TenantContext;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\Rule;

class StockController extends Controller
{
    public function stockIn(StockRequest $request, StockService $stock): JsonResponse
    {
        $data = $request->validated();

        $movement = $stock->stockIn(
            $data['variant_id'], (string) $data['quantity'], $request->user(),
            isset($data['unit_cost']) ? (string) $data['unit_cost'] : null,
            $data['vendor_id'] ?? null, $data['note'] ?? null,
        );

        return $this->respond($movement, 201);
    }

    public function stockOut(StockRequest $request, StockService $stock): JsonResponse
    {
        $data = $request->validated();

        return $this->respond($stock->stockOut($data['variant_id'], (string) $data['quantity'], $request->user(), $data['note']), 201);
    }

    public function adjust(StockRequest $request, StockService $stock): JsonResponse
    {
        $data = $request->validated();
        $movement = $stock->adjustTo($data['variant_id'], (string) $data['new_quantity'], $request->user(), $data['note'] ?? null);

        if ($movement === null) {
            // The count matched; nothing to record.
            return response()->json(['data' => null, 'meta' => [
                'stock_quantity' => ProductVariant::query()->whereKey($data['variant_id'])->value('stock_quantity'),
                'changed' => false,
            ]]);
        }

        return $this->respond($movement, 201);
    }

    public function movements(Request $request): AnonymousResourceCollection
    {
        $filters = $request->validate([
            'variant_id' => ['sometimes', 'integer'],
            'product_id' => ['sometimes', 'integer'],
            'type' => ['sometimes', Rule::enum(StockMovementType::class)],
            'from' => ['sometimes', 'date'],
            'to' => ['sometimes', 'date'],
        ]);

        return StockMovementResource::collection(
            StockMovement::query()
                ->with(['variant.product', 'vendor'])
                ->when($filters['variant_id'] ?? null, fn ($q, $id) => $q->where('product_variant_id', $id))
                ->when($filters['product_id'] ?? null, fn ($q, $id) => $q->whereHas('variant', fn ($v) => $v->withTrashed()->where('product_id', $id)))
                ->when($filters['type'] ?? null, fn ($q, $type) => $q->where('type', $type))
                ->when($filters['from'] ?? null, fn ($q, $from) => $q->where('created_at', '>=', $from))
                ->when($filters['to'] ?? null, fn ($q, $to) => $q->where('created_at', '<=', $to))
                ->latest('id')
                ->paginate(min($request->integer('per_page', 30), 100))
        );
    }

    /** Counts for the dashboard: products, and how many have a low or empty variant. */
    public function summary(TenantContext $tenant): JsonResponse
    {
        $defaultThreshold = $tenant->shop()->resolvedSettings()['low_stock_threshold'];

        $having = fn (string $state) => Product::query()->whereHas('variants', function (Builder $q) use ($state, $defaultThreshold) {
            $q->join('products as p', 'p.id', '=', 'product_variants.product_id');
            $state === 'out'
                ? $q->where('product_variants.stock_quantity', '<=', 0)
                : $q->where('product_variants.stock_quantity', '>', 0)
                    ->whereRaw('product_variants.stock_quantity <= coalesce(p.low_stock_threshold, ?)', [$defaultThreshold]);
        })->count();

        return response()->json(['data' => [
            'total_products' => Product::query()->count(),
            'low_stock_products' => $having('low'),
            'out_of_stock_products' => $having('out'),
        ]]);
    }

    private function respond(StockMovement $movement, int $status): JsonResponse
    {
        return (new StockMovementResource($movement->load(['variant.product', 'vendor'])))->response()->setStatusCode($status);
    }
}
