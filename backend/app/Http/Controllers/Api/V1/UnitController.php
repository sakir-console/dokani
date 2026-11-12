<?php

namespace App\Http\Controllers\Api\V1;

use App\Exceptions\ApiException;
use App\Http\Controllers\Controller;
use App\Http\Resources\UnitResource;
use App\Models\Product;
use App\Models\Unit;
use App\Services\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\Rule;

/**
 * Units are the built-in list plus the shop's own. Only the shop's own can be changed.
 */
class UnitController extends Controller
{
    public function index(): AnonymousResourceCollection
    {
        // Built-in units first, in seeded order; then the shop's own by name.
        return UnitResource::collection(
            Unit::query()->orderByRaw('shop_id is not null')->orderByRaw('case when shop_id is null then id end')->orderBy('name')->get()
        );
    }

    public function store(Request $request, TenantContext $tenant): JsonResponse
    {
        $unit = Unit::create($this->validated($request, $tenant));

        return (new UnitResource($unit))->response()->setStatusCode(201);
    }

    public function update(Request $request, Unit $unit, TenantContext $tenant): UnitResource
    {
        $this->assertCustom($unit);
        $unit->update($this->validated($request, $tenant, $unit));

        return new UnitResource($unit);
    }

    public function destroy(Unit $unit): JsonResponse
    {
        $this->assertCustom($unit);

        if (Product::query()->where('unit_id', $unit->id)->exists()) {
            throw ApiException::conflict('UNIT_IN_USE', __('This unit is used by products and cannot be deleted.'));
        }

        $unit->delete();

        return response()->json(null, 204);
    }

    private function assertCustom(Unit $unit): void
    {
        if ($unit->isBuiltIn()) {
            throw ApiException::forbidden('UNIT_BUILT_IN', __('Built-in units cannot be changed.'));
        }
    }

    /** @return array<string, mixed> */
    private function validated(Request $request, TenantContext $tenant, ?Unit $unit = null): array
    {
        $required = $unit === null ? 'required' : 'sometimes';

        // A custom unit may not reuse the name of a built-in unit or of another of the shop's units.
        $unique = Rule::unique('units', 'name')
            ->where(fn ($q) => $q->whereNull('shop_id')->orWhere('shop_id', $tenant->id()))
            ->ignore($unit?->id);

        return $request->validate([
            'name' => [$required, 'string', 'max:40', $unique],
            'short_name' => [$required, 'string', 'max:12'],
            'allows_decimal' => ['sometimes', 'boolean'],
        ]);
    }
}
