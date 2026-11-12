<?php

namespace Database\Factories;

use App\Models\Product;
use App\Models\Unit;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * Bare product row for tests that only need one to exist. Real products are
 * created through ProductService, which also creates the variants.
 *
 * @extends Factory<Product>
 */
class ProductFactory extends Factory
{
    public function definition(): array
    {
        return [
            'name' => ucfirst(fake()->unique()->words(2, true)),
            'unit_id' => fn () => Unit::query()->where('name', 'Piece')->value('id'),
        ];
    }
}
