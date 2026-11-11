<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\UpdateShopRequest;
use App\Http\Requests\Api\V1\UpdateShopSettingsRequest;
use App\Http\Requests\Api\V1\UploadLogoRequest;
use App\Http\Resources\ShopResource;
use App\Models\Shop;
use App\Services\Audit\AuditLogger;
use App\Services\Media\ImageStore;
use App\Services\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;

class ShopController extends Controller
{
    // Request-scoped services are injected per method, never through the constructor.

    public function show(TenantContext $tenant): ShopResource
    {
        return new ShopResource($tenant->shop());
    }

    public function update(UpdateShopRequest $request, TenantContext $tenant, AuditLogger $audit): ShopResource
    {
        $shop = $tenant->shop();
        $shop->fill($request->validated());

        if ($shop->isDirty()) {
            $changed = array_keys($shop->getDirty());
            $old = array_intersect_key($shop->getRawOriginal(), array_flip($changed));
            $shop->save();
            $audit->log('shop.updated', $shop, $old, array_intersect_key($shop->getAttributes(), array_flip($changed)));
        }

        return new ShopResource($shop);
    }

    public function uploadLogo(UploadLogoRequest $request, TenantContext $tenant, ImageStore $images): ShopResource
    {
        $shop = $tenant->shop();
        $previous = $shop->logo_path;

        $shop->logo_path = $images->store($request->file('logo'), "shops/{$shop->id}", config('dokani.uploads.logo_max_px'));
        $shop->save();
        $images->delete($previous);

        return new ShopResource($shop);
    }

    public function deleteLogo(TenantContext $tenant, ImageStore $images): ShopResource
    {
        $shop = $tenant->shop();
        $previous = $shop->logo_path;

        $shop->logo_path = null;
        $shop->save();
        $images->delete($previous);

        return new ShopResource($shop);
    }

    public function settings(TenantContext $tenant): JsonResponse
    {
        return response()->json(['data' => $tenant->shop()->resolvedSettings()]);
    }

    public function updateSettings(UpdateShopSettingsRequest $request, TenantContext $tenant, AuditLogger $audit): JsonResponse
    {
        $shop = $tenant->shop();
        $old = $shop->resolvedSettings();

        // Only known keys are ever stored; anything else in the request is dropped by validation.
        $shop->settings = array_merge($old, array_intersect_key($request->validated(), Shop::DEFAULT_SETTINGS));
        $shop->save();

        $audit->log('shop.settings_updated', $shop, $old, $shop->resolvedSettings());

        return response()->json(['data' => $shop->resolvedSettings()]);
    }
}
