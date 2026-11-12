<?php

namespace Database\Factories;

use App\Models\GlobalProduct;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<GlobalProduct> */
class GlobalProductFactory extends Factory
{
    public function definition(): array
    {
        return [
            'name' => ucfirst(fake()->unique()->words(3, true)),
            'default_unit' => 'Piece',
        ];
    }
}
