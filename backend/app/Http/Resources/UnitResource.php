<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class UnitResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'name_bn' => $this->name_bn,
            'short_name' => $this->short_name,
            'allows_decimal' => $this->allows_decimal,
            'is_built_in' => $this->shop_id === null,
        ];
    }
}
