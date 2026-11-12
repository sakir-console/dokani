<?php

namespace Database\Factories;

use App\Models\Brand;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<Brand> */
class BrandFactory extends Factory
{
    public function definition(): array
    {
        return ['name' => ucfirst(fake()->unique()->word()).' '.fake()->unique()->numberBetween(1, 99999)];
    }
}
