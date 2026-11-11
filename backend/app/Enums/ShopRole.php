<?php

namespace App\Enums;

enum ShopRole: string
{
    case Owner = 'owner';
    case Manager = 'manager';
    case Cashier = 'cashier';

    /** @return list<string> */
    public function permissions(): array
    {
        return config('dokani.roles.'.$this->value, []);
    }

    public function can(string $permission): bool
    {
        $granted = $this->permissions();

        return in_array('*', $granted, true) || in_array($permission, $granted, true);
    }
}
