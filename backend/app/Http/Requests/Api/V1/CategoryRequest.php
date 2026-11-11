<?php

namespace App\Http\Requests\Api\V1;

use App\Models\Category;
use App\Rules\ExistsInShop;
use App\Services\Tenancy\TenantContext;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class CategoryRequest extends FormRequest
{
    public function rules(): array
    {
        $category = $this->route('category');
        $parentId = $this->has('parent_id') ? $this->input('parent_id') : $category?->parent_id;

        // Names are unique among the live categories under the same parent, in this shop only.
        $uniqueName = Rule::unique('categories', 'name')
            ->where('shop_id', app(TenantContext::class)->id())
            ->where(fn ($q) => $parentId === null ? $q->whereNull('parent_id') : $q->where('parent_id', $parentId))
            ->whereNull('deleted_at')
            ->ignore($category?->id);

        return [
            'name' => [$this->isMethod('POST') ? 'required' : 'sometimes', 'required', 'string', 'max:100', $uniqueName],
            'parent_id' => ['sometimes', 'nullable', 'integer', new ExistsInShop(Category::class), Rule::notIn(array_filter([$category?->id]))],
            'sort_order' => ['sometimes', 'integer', 'min:0', 'max:65535'],
        ];
    }
}
