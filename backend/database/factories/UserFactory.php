<?php

namespace Database\Factories;

use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<User> */
class UserFactory extends Factory
{
    public function definition(): array
    {
        return [
            'name' => fake()->name(),
            'phone' => '01'.fake()->unique()->numerify('7########'),
            'password' => 'password',
            'locale' => 'bn',
        ];
    }
}
