<?php

namespace App\Services\Tenancy;

use LogicException;

class MissingTenantException extends LogicException
{
    public static function forModel(string $model): self
    {
        return new self("{$model} is shop-owned and was used without a shop in the tenant context.");
    }
}
