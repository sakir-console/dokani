<?php

namespace Tests\Feature\Api;

use App\Models\Category;
use Tests\TestCase;

class CategoryTest extends TestCase
{
    public function test_categories_can_be_created_listed_updated_and_deleted(): void
    {
        $shop = $this->createShop();

        $id = $this->asOwnerOf($shop)->postJson('/api/v1/categories', ['name' => 'Beverages'])
            ->assertCreated()->assertJsonPath('data.name', 'Beverages')->assertJsonPath('data.sort_order', 0)->json('data.id');

        $child = $this->asOwnerOf($shop)->postJson('/api/v1/categories', ['name' => 'Juice', 'parent_id' => $id])
            ->assertCreated()->assertJsonPath('data.parent_id', $id)->json('data.id');

        $this->asOwnerOf($shop)->getJson('/api/v1/categories')->assertOk()->assertJsonCount(2, 'data');
        $this->asOwnerOf($shop)->getJson('/api/v1/categories?q=jui')->assertOk()->assertJsonCount(1, 'data');

        $this->asOwnerOf($shop)->patchJson("/api/v1/categories/{$child}", ['name' => 'Fruit juice'])
            ->assertOk()->assertJsonPath('data.name', 'Fruit juice')->assertJsonPath('data.parent_id', $id);

        $this->asOwnerOf($shop)->deleteJson("/api/v1/categories/{$id}")
            ->assertConflict()->assertJsonPath('code', 'CATEGORY_HAS_CHILDREN');

        $this->asOwnerOf($shop)->deleteJson("/api/v1/categories/{$child}")->assertNoContent();
        $this->asOwnerOf($shop)->deleteJson("/api/v1/categories/{$id}")->assertNoContent();
        $this->asOwnerOf($shop)->getJson('/api/v1/categories')->assertJsonCount(0, 'data');
    }

    public function test_names_are_unique_under_the_same_parent_and_reusable_after_deletion(): void
    {
        $shop = $this->createShop();

        $id = $this->asOwnerOf($shop)->postJson('/api/v1/categories', ['name' => 'Snacks'])->json('data.id');
        $this->asOwnerOf($shop)->postJson('/api/v1/categories', ['name' => 'Snacks'])
            ->assertUnprocessable()->assertJsonValidationErrors('name');

        // Allowed under a different parent, and when renaming a category to its own name.
        $this->asOwnerOf($shop)->postJson('/api/v1/categories', ['name' => 'Snacks', 'parent_id' => $id])->assertCreated();
        $this->asOwnerOf($shop)->patchJson("/api/v1/categories/{$id}", ['name' => 'Snacks'])->assertOk();

        $other = $this->asOwnerOf($shop)->postJson('/api/v1/categories', ['name' => 'Dairy'])->json('data.id');
        $this->asOwnerOf($shop)->deleteJson("/api/v1/categories/{$other}")->assertNoContent();
        $this->asOwnerOf($shop)->postJson('/api/v1/categories', ['name' => 'Dairy'])->assertCreated();
    }

    public function test_a_category_cannot_become_its_own_ancestor(): void
    {
        $shop = $this->createShop();

        [$parent, $child, $grandchild] = $this->tenant()->runFor($shop, function () {
            $parent = Category::factory()->create();
            $child = Category::factory()->create(['parent_id' => $parent->id]);
            $grandchild = Category::factory()->create(['parent_id' => $child->id]);

            return [$parent, $child, $grandchild];
        });

        $this->asOwnerOf($shop)->patchJson("/api/v1/categories/{$parent->id}", ['parent_id' => $parent->id])
            ->assertUnprocessable();
        $this->asOwnerOf($shop)->patchJson("/api/v1/categories/{$parent->id}", ['parent_id' => $grandchild->id])
            ->assertUnprocessable()->assertJsonPath('code', 'CATEGORY_CYCLE');

        $this->asOwnerOf($shop)->patchJson("/api/v1/categories/{$grandchild->id}", ['parent_id' => $parent->id])->assertOk();
    }
}
