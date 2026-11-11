<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\UpdateProfileRequest;
use App\Http\Resources\SessionResource;
use App\Services\Tenancy\TenantContext;
use Illuminate\Http\Request;

class MeController extends Controller
{
    // TenantContext is request-scoped, so it is injected per method call —
    // never through the constructor, where a reused controller would keep a stale one.

    public function show(Request $request, TenantContext $tenant): SessionResource
    {
        return new SessionResource($request->user(), $tenant->shop(), $tenant->membership());
    }

    public function update(UpdateProfileRequest $request, TenantContext $tenant): SessionResource
    {
        $request->user()->update($request->validated());

        return $this->show($request, $tenant);
    }
}
