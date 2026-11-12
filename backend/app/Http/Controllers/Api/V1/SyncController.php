<?php

namespace App\Http\Controllers\Api\V1;

use App\Exceptions\ApiException;
use App\Http\Controllers\Controller;
use App\Http\Resources\CategoryResource;
use App\Http\Resources\CustomerResource;
use App\Http\Resources\ProductResource;
use App\Models\Category;
use App\Models\Customer;
use App\Models\Device;
use App\Models\Product;
use App\Services\Sync\PushService;
use App\Services\Tenancy\TenantContext;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

/**
 * Keeps a phone's local copy in step with the server.
 *
 * Pull: "what changed since my last sync?" — changed rows plus the ids of
 * deleted ones. Without `since` it returns everything (the first sync).
 * The phone stores the `cursor` from the first page of a round and sends it
 * as `since` next time. The cursor is set a few seconds in the past, so a
 * row saved during the request is sent again rather than missed; applying a
 * row twice is harmless.
 *
 * Push: see PushService.
 */
class SyncController extends Controller
{
    private const PAGE = 200;

    public function products(Request $request): JsonResponse
    {
        [$since, $cursor] = $this->window($request);

        $query = Product::query()
            ->when($since, function (Builder $q) use ($since) {
                // A stock or price change only touches the variant, so both levels are checked.
                $q->withTrashed()->where(fn (Builder $q) => $q
                    ->where('products.updated_at', '>=', $since)
                    ->orWhere('products.deleted_at', '>=', $since)
                    ->orWhereHas('variants', fn (Builder $v) => $v->withTrashed()
                        ->where(fn (Builder $v) => $v->where('updated_at', '>=', $since)->orWhere('deleted_at', '>=', $since))));
            })
            ->with(['variants.barcodes', 'category', 'brand', 'unit', 'vendor'])
            ->orderBy('products.id');

        $page = $query->paginate(self::PAGE);
        $items = collect($page->items());

        return response()->json([
            'data' => ProductResource::collection($items->reject->trashed()->values())->resolve($request),
            'deleted_ids' => $items->filter->trashed()->pluck('id')->values(),
            'meta' => ['current_page' => $page->currentPage(), 'last_page' => $page->lastPage(), 'cursor' => $cursor],
        ]);
    }

    public function customers(Request $request): JsonResponse
    {
        [$since, $cursor] = $this->window($request);

        $page = Customer::query()
            ->when($since, fn (Builder $q) => $q->withTrashed()
                ->where(fn (Builder $q) => $q->where('updated_at', '>=', $since)->orWhere('deleted_at', '>=', $since)))
            ->orderBy('id')
            ->paginate(self::PAGE);
        $items = collect($page->items());

        return response()->json([
            'data' => CustomerResource::collection($items->reject->trashed()->values())->resolve($request),
            'deleted_ids' => $items->filter->trashed()->pluck('id')->values(),
            'meta' => ['current_page' => $page->currentPage(), 'last_page' => $page->lastPage(), 'cursor' => $cursor],
        ]);
    }

    public function categories(Request $request): JsonResponse
    {
        [$since, $cursor] = $this->window($request);

        $items = Category::query()
            ->when($since, fn (Builder $q) => $q->withTrashed()
                ->where(fn (Builder $q) => $q->where('updated_at', '>=', $since)->orWhere('deleted_at', '>=', $since)))
            ->orderBy('id')->get();

        return response()->json([
            'data' => CategoryResource::collection($items->reject->trashed()->values())->resolve($request),
            'deleted_ids' => $items->filter->trashed()->pluck('id')->values(),
            'meta' => ['cursor' => $cursor],
        ]);
    }

    public function push(Request $request, PushService $push, TenantContext $tenant): JsonResponse
    {
        $data = $request->validate([
            'device' => ['sometimes', 'array'],
            'device.uuid' => ['required_with:device', 'uuid'],
            'device.name' => ['sometimes', 'nullable', 'string', 'max:100'],
            'device.platform' => ['sometimes', 'nullable', 'string', 'max:20'],
            'device.app_version' => ['sometimes', 'nullable', 'string', 'max:20'],
            // Small batches: a slow connection finishes each one, and progress is kept between them.
            'sales' => ['sometimes', 'array', 'max:50'],
            'due_collections' => ['sometimes', 'array', 'max:50'],
        ]);

        $role = $tenant->membership()?->role;
        $device = $this->touchDevice($request, $data['device'] ?? null);

        // Sales first: a due collection may be for a customer created by one of them.
        $sales = ($data['sales'] ?? []) === [] ? [] : (
            $role?->can('pos.sell')
                ? $push->pushSales($data['sales'], $request->user(), $device?->id)
                : $this->forbidden($data['sales'])
        );

        $collections = ($data['due_collections'] ?? []) === [] ? [] : (
            $role?->can('due.collect')
                ? $push->pushDueCollections($data['due_collections'], $request->user())
                : $this->forbidden($data['due_collections'])
        );

        $device?->forceFill(['last_synced_at' => now()])->save();

        return response()->json(['data' => ['sales' => $sales, 'due_collections' => $collections]]);
    }

    public function registerDevice(Request $request): JsonResponse
    {
        $data = $request->validate([
            'uuid' => ['required', 'uuid'],
            'name' => ['sometimes', 'nullable', 'string', 'max:100'],
            'platform' => ['sometimes', 'nullable', 'string', 'max:20'],
            'app_version' => ['sometimes', 'nullable', 'string', 'max:20'],
        ]);

        $device = $this->touchDevice($request, $data);

        return response()->json(['data' => ['id' => $device->id, 'uuid' => $device->device_uuid]]);
    }

    /** @param array{uuid: string, name?: ?string, platform?: ?string, app_version?: ?string}|null $info */
    private function touchDevice(Request $request, ?array $info): ?Device
    {
        if ($info === null) {
            return null;
        }

        $device = Device::query()->firstOrNew(['device_uuid' => $info['uuid']]);
        $device->fill(array_filter([
            'name' => $info['name'] ?? null,
            'platform' => $info['platform'] ?? null,
            'app_version' => $info['app_version'] ?? null,
        ]));
        $device->user_id = $request->user()->id;
        $device->last_seen_at = now();
        $device->save();

        return $device;
    }

    /**
     * @param  list<mixed>  $records
     * @return list<array<string, mixed>>
     */
    private function forbidden(array $records): array
    {
        return array_map(fn ($record) => [
            'client_uuid' => is_array($record) ? ($record['client_uuid'] ?? null) : null,
            'status' => 'failed',
            'code' => 'FORBIDDEN',
            'message' => __('You do not have permission to do this.'),
        ], array_values($records));
    }

    /** @return array{0: ?Carbon, 1: string} the lower bound to query from, and the cursor to hand back */
    private function window(Request $request): array
    {
        $input = $request->validate(['since' => ['sometimes', 'nullable', 'date']]);

        try {
            $since = empty($input['since']) ? null : Carbon::parse($input['since'])->utc();
        } catch (\Throwable) {
            throw new ApiException('VALIDATION_FAILED', __('The sync position is not valid.'), 422);
        }

        return [$since, now()->subSeconds(5)->toIso8601String()];
    }
}
