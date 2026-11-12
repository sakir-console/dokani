<?php

namespace App\Services\Customers;

use App\Enums\LedgerType;
use App\Exceptions\ApiException;
use App\Models\Customer;
use App\Models\User;
use App\Support\Dec;
use App\Support\Phone;
use Illuminate\Support\Facades\DB;

class CustomerService
{
    public function __construct(private readonly LedgerService $ledger) {}

    /**
     * @param  array{name: string, phone: string, address?: ?string, notes?: ?string, credit_limit?: mixed, opening_due?: mixed}  $data
     */
    public function create(array $data, ?User $actor): Customer
    {
        return DB::transaction(function () use ($data, $actor) {
            $phone = Phone::normalize($data['phone']);

            if (Customer::query()->where('phone', $phone)->exists()) {
                throw new ApiException('CUSTOMER_EXISTS', __('A customer with this mobile number already exists.'), 422, [
                    'phone' => [__('A customer with this mobile number already exists.')],
                ]);
            }

            $customer = $this->reviveOrNew($phone);
            $customer->fill([
                'name' => $data['name'],
                'address' => $data['address'] ?? null,
                'notes' => $data['notes'] ?? null,
                'credit_limit' => isset($data['credit_limit']) ? Dec::money($data['credit_limit']) : null,
            ]);
            $customer->save();

            // An opening balance is a ledger entry like any other, never a bare number.
            if (Dec::of($data['opening_due'] ?? 0)->isPositive()) {
                $this->ledger->debit($customer->id, Dec::of($data['opening_due']), LedgerType::Opening, $actor);
            }

            return $customer->refresh();
        });
    }

    /**
     * The customer with this phone in the current shop; created when new.
     * Used at checkout when a sale leaves a due.
     */
    public function findOrCreate(string $phone, ?string $name, ?User $actor): Customer
    {
        $phone = Phone::normalize($phone);
        $existing = Customer::query()->where('phone', $phone)->first();

        if ($existing !== null) {
            return $existing;
        }

        if ($name === null || trim($name) === '') {
            throw new ApiException('CUSTOMER_NAME_REQUIRED', __('Enter the customer\'s name to create their account.'), 422, [
                'customer.name' => [__('Enter the customer\'s name to create their account.')],
            ]);
        }

        $customer = $this->reviveOrNew($phone);
        $customer->name = trim($name);
        $customer->save();

        return $customer;
    }

    /** A deleted customer with the same phone comes back with their history instead of colliding. */
    private function reviveOrNew(string $phone): Customer
    {
        $deleted = Customer::query()->onlyTrashed()->where('phone', $phone)->first();

        if ($deleted !== null) {
            $deleted->restore();

            return $deleted;
        }

        $customer = new Customer;
        $customer->phone = $phone;

        return $customer;
    }
}
