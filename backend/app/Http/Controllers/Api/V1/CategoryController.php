<?php

namespace App\Http\Controllers\Api\V1;

use App\Exceptions\ApiException;
use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\CategoryRequest;
use App\Http\Resources\CategoryResource;
use App\Models\Category;
use App\Models\Product;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\DB;

/**
 * Category has the BelongsToShop trait, so every query here — including the
 * {category} route binding — only ever sees the current shop's rows.
 */
class CategoryController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        $categories = Category::query()
            ->when($request->filled('q'), fn ($q) => $q->where('name', 'like', '%'.addcslashes($request->string('q')->toString(), '%_\\').'%'))
            ->orderBy('sort_order')->orderBy('name')
            ->get();

        return CategoryResource::collection($categories);
    }

    public function store(CategoryRequest $request): JsonResponse
    {
        $category = Category::create($request->validated());

        return (new CategoryResource($category))->response()->setStatusCode(201);
    }

    public function show(Category $category): CategoryResource
    {
        return new CategoryResource($category);
    }

    public function update(CategoryRequest $request, Category $category): CategoryResource
    {
        $data = $request->validated();

        if (array_key_exists('parent_id', $data) && $data['parent_id'] !== null && $this->isDescendant($category, (int) $data['parent_id'])) {
            throw new ApiException('CATEGORY_CYCLE', __('A category cannot be moved under one of its own sub-categories.'), 422);
        }

        $category->update($data);

        return new CategoryResource($category);
    }

    public function destroy(Category $category): JsonResponse
    {
        if ($category->children()->exists()) {
            throw ApiException::conflict('CATEGORY_HAS_CHILDREN', __('Remove or move the sub-categories first.'));
        }

        DB::transaction(function () use ($category) {
            // Products stay; they simply have no category afterwards.
            Product::query()->where('category_id', $category->id)->update(['category_id' => null]);
            $category->delete();
        });

        return response()->json(null, 204);
    }

    private function isDescendant(Category $category, int $candidateParentId): bool
    {
        $seen = [];
        $current = Category::query()->find($candidateParentId);

        while ($current !== null && ! isset($seen[$current->id])) {
            if ($current->id === $category->id) {
                return true;
            }
            $seen[$current->id] = true;
            $current = $current->parent_id ? Category::query()->find($current->parent_id) : null;
        }

        return false;
    }
}
