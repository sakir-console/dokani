<?php

namespace Tests\Feature\Api;

use App\Enums\ShopRole;
use App\Models\Customer;
use App\Models\CustomerLedger;
use App\Models\Payment;
use App\Models\Sale;
use App\Support\Dec;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Payments and dues: split payment, partial payment, the rule that a due
 * needs a customer, finding or creating the customer by phone, collecting
 * dues in instalments, and the ledger that records it all.
 */
class DueTest extends TestCase
{
    private function shopWithItem(string $price = '1000'): array
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop, [], [['purchase_price' => '700', 'selling_price' => $price, 'stock_quantity' => 100]])->variants[0];

        return [$shop, $variant];
    }

    private function customerIn($shop, array $attributes = []): Customer
    {
        return $this->tenant()->runFor($shop, fn () => Customer::factory()->create($attributes));
    }

    private function dueOf(Customer $customer): string
    {
        return $this->tenant()->withoutTenancy(fn () => Customer::query()->withTrashed()->whereKey($customer->id)->value('current_due'));
    }

    // --- The due rule ---------------------------------------------------------------

    public function test_a_sale_with_a_due_is_refused_without_a_customer(): void
    {
        [$shop, $variant] = $this->shopWithItem();

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '1000', [
            'payments' => [['method' => 'cash', 'amount' => '600']], 'due_amount' => '400',
        ]))->assertUnprocessable()
            ->assertJsonPath('code', 'DUE_REQUIRES_CUSTOMER')
            ->assertJsonValidationErrors('customer.phone');

        $this->tenant()->runFor($shop, fn () => $this->assertSame(0, Sale::query()->count()));
    }

    public function test_a_partial_payment_puts_the_rest_on_the_customers_ledger(): void
    {
        // Grand total 1,000 · paid 600 · due 400
        [$shop, $variant] = $this->shopWithItem();

        $response = $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '1000', [
            'payments' => [['method' => 'cash', 'amount' => '600']],
            'due_amount' => '400',
            'customer' => ['name' => 'Rahim Uddin', 'phone' => '+880 1712-345678'],
        ]));

        $response->assertCreated()
            ->assertJsonPath('data.paid_amount', '600.00')
            ->assertJsonPath('data.due_amount', '400.00')
            ->assertJsonPath('data.customer.name', 'Rahim Uddin')
            ->assertJsonPath('data.customer.phone', '01712345678')
            ->assertJsonPath('data.customer.current_due', '400.00');

        $this->tenant()->runFor($shop, function () use ($response) {
            $customer = Customer::query()->sole();
            $this->assertSame('400.00', $customer->current_due);
            $this->assertSame('1000.00', $customer->total_purchases);
            $this->assertSame('600.00', $customer->total_paid);

            $entry = CustomerLedger::query()->sole();
            $this->assertSame('sale_due', $entry->type->value);
            $this->assertSame('400.00', $entry->debit);
            $this->assertSame('0.00', $entry->credit);
            $this->assertSame('400.00', $entry->balance_after);
            $this->assertSame($response->json('data.id'), $entry->sale_id);

            // "Due" is never stored as a payment.
            $this->assertSame(['cash'], Payment::query()->pluck('method')->map->value->all());
        });
    }

    public function test_a_split_payment_records_each_method_and_the_due(): void
    {
        // Cash 500 · bKash 200 · due 300
        [$shop, $variant] = $this->shopWithItem();

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '1000', [
            'payments' => [
                ['method' => 'cash', 'amount' => '500', 'received_amount' => '500'],
                ['method' => 'bkash', 'amount' => '200', 'transaction_id' => '9XK2L0AB', 'reference' => '01812345678'],
            ],
            'due_amount' => '300',
            'customer' => ['name' => 'Karim', 'phone' => '01812345678'],
        ]))->assertCreated()
            ->assertJsonPath('data.paid_amount', '700.00')
            ->assertJsonPath('data.due_amount', '300.00')
            ->assertJsonCount(2, 'data.payments')
            ->assertJsonPath('data.payments.1.method', 'bkash')
            ->assertJsonPath('data.payments.1.amount', '200.00')
            ->assertJsonPath('data.payments.1.transaction_id', '9XK2L0AB')
            // Typed in by the cashier: never presented as confirmed by bKash.
            ->assertJsonPath('data.payments.1.verification', 'unverified');
    }

    public function test_total_must_equal_paid_plus_due_exactly(): void
    {
        [$shop, $variant] = $this->shopWithItem();
        $customer = ['customer' => ['name' => 'X', 'phone' => '01712345678']];
        $post = fn (array $overrides) => $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '1000', $overrides + $customer));

        // Paid + due short of the total.
        $post(['payments' => [['method' => 'cash', 'amount' => '600']], 'due_amount' => '300'])
            ->assertUnprocessable()->assertJsonPath('code', 'PAYMENT_MISMATCH');
        // Paid + due more than the total.
        $post(['payments' => [['method' => 'cash', 'amount' => '600']], 'due_amount' => '500'])
            ->assertUnprocessable()->assertJsonPath('code', 'PAYMENT_MISMATCH');
        // Paying less without declaring a due does not silently create one.
        $post(['payments' => [['method' => 'cash', 'amount' => '600']], 'due_amount' => '0'])
            ->assertUnprocessable()->assertJsonPath('code', 'PAYMENT_MISMATCH');
        // An overpayment is not a payment.
        $post(['payments' => [['method' => 'bkash', 'amount' => '1200']], 'due_amount' => '0'])
            ->assertUnprocessable()->assertJsonPath('code', 'PAYMENT_MISMATCH');
        // No payments and no due.
        $post(['payments' => [], 'due_amount' => '0'])->assertUnprocessable()->assertJsonPath('code', 'PAYMENT_MISMATCH');

        $this->tenant()->runFor($shop, function () {
            $this->assertSame(0, Sale::query()->count());
            $this->assertSame(0, Customer::query()->count(), 'A rejected sale does not leave a new customer behind.');
        });
    }

    public function test_cash_received_gives_change_and_cannot_be_less_than_the_amount(): void
    {
        // Bill 500 · received 1,000 · change 500
        [$shop, $variant] = $this->shopWithItem('500');

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '500', [
            'payments' => [['method' => 'cash', 'amount' => '500', 'received_amount' => '1000']],
        ]))->assertCreated()
            ->assertJsonPath('data.paid_amount', '500.00')
            ->assertJsonPath('data.change_amount', '500.00')
            ->assertJsonPath('data.payments.0.amount', '500.00');

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '500', [
            'payments' => [['method' => 'cash', 'amount' => '500', 'received_amount' => '400']],
        ]))->assertUnprocessable()->assertJsonPath('code', 'RECEIVED_LESS_THAN_AMOUNT');
    }

    public function test_a_sale_entirely_on_due_needs_no_payment_rows(): void
    {
        [$shop, $variant] = $this->shopWithItem();

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '1000', [
            'payments' => [], 'due_amount' => '1000', 'customer' => ['name' => 'Karim', 'phone' => '01812345678'],
        ]))->assertCreated()->assertJsonPath('data.paid_amount', '0.00')->assertJsonPath('data.due_amount', '1000.00');
    }

    // --- Finding or creating the customer ------------------------------------------

    public function test_an_existing_customer_is_found_by_phone_and_not_duplicated(): void
    {
        [$shop, $variant] = $this->shopWithItem();
        $existing = $this->customerIn($shop, ['name' => 'Rahim Uddin', 'phone' => '01712345678']);

        $this->asOwnerOf($shop)->getJson('/api/v1/customers/lookup?phone='.urlencode('+8801712345678'))
            ->assertOk()->assertJsonPath('data.id', $existing->id)->assertJsonPath('data.name', 'Rahim Uddin');

        // At checkout the phone alone is enough; the name typed there does not rename the customer.
        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '1000', [
            'payments' => [], 'due_amount' => '1000', 'customer' => ['phone' => '01712345678', 'name' => 'Someone Else'],
        ]))->assertCreated()->assertJsonPath('data.customer.id', $existing->id)->assertJsonPath('data.customer.name', 'Rahim Uddin');

        $this->tenant()->runFor($shop, fn () => $this->assertSame(1, Customer::query()->count()));
    }

    public function test_a_new_customer_needs_a_name_as_well_as_a_phone(): void
    {
        [$shop, $variant] = $this->shopWithItem();
        $due = ['payments' => [], 'due_amount' => '1000'];

        $this->asOwnerOf($shop)->getJson('/api/v1/customers/lookup?phone=01999999999')
            ->assertNotFound()->assertJsonPath('code', 'CUSTOMER_NOT_FOUND');

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '1000', $due + ['customer' => ['phone' => '01999999999']]))
            ->assertUnprocessable()->assertJsonPath('code', 'CUSTOMER_NAME_REQUIRED')->assertJsonValidationErrors('customer.name');

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '1000', $due + ['customer' => ['phone' => '12345', 'name' => 'X']]))
            ->assertUnprocessable()->assertJsonValidationErrors('customer.phone');

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '1000', $due + ['customer' => ['phone' => '01999999999', 'name' => 'New Person']]))
            ->assertCreated()->assertJsonPath('data.customer.name', 'New Person');
    }

    public function test_a_customer_can_also_be_chosen_by_id_and_linked_to_a_fully_paid_sale(): void
    {
        [$shop, $variant] = $this->shopWithItem();
        $customer = $this->customerIn($shop);

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '1000', ['customer_id' => $customer->id]))
            ->assertCreated()->assertJsonPath('data.customer.id', $customer->id)->assertJsonPath('data.due_amount', '0.00');

        $this->assertSame('0.00', $this->dueOf($customer));
        $this->tenant()->runFor($shop, fn () => $this->assertSame(0, CustomerLedger::query()->count(), 'No ledger entry without a due.'));
        $this->asOwnerOf($shop)->getJson("/api/v1/customers/{$customer->id}")->assertJsonPath('data.total_purchases', '1000.00')->assertJsonPath('data.total_paid', '1000.00');
    }

    public function test_a_credit_limit_caps_how_much_a_customer_can_owe(): void
    {
        [$shop, $variant] = $this->shopWithItem();
        $customer = $this->customerIn($shop, ['credit_limit' => '1500']);
        $onDue = fn () => $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '1000', [
            'payments' => [], 'due_amount' => '1000', 'customer_id' => $customer->id,
        ]));

        $onDue()->assertCreated();
        $onDue()->assertUnprocessable()->assertJsonPath('code', 'CREDIT_LIMIT_EXCEEDED');
        $this->assertSame('1000.00', $this->dueOf($customer));
    }

    // --- Collecting dues -------------------------------------------------------------

    public function test_a_due_can_be_paid_off_in_instalments_by_different_methods(): void
    {
        [$shop, $variant] = $this->shopWithItem();
        $customer = $this->customerIn($shop);
        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '1000', [
            'payments' => [['method' => 'cash', 'amount' => '400']], 'due_amount' => '600', 'customer_id' => $customer->id,
        ]))->assertCreated();

        $collect = fn (array $data) => $this->asOwnerOf($shop)->postJson("/api/v1/customers/{$customer->id}/collect-due", ['client_uuid' => (string) Str::uuid()] + $data);

        $collect(['amount' => '250', 'method' => 'cash'])->assertCreated()
            ->assertJsonPath('data.type', 'due_collection')
            ->assertJsonPath('data.amount', '250.00')
            ->assertJsonPath('meta.customer.current_due', '350.00');

        $collect(['amount' => '100.50', 'method' => 'bkash', 'transaction_id' => 'TX123'])->assertCreated()
            ->assertJsonPath('data.verification', 'unverified')
            ->assertJsonPath('meta.customer.current_due', '249.50');

        // More than is owed is refused; exactly what is owed clears the balance.
        $collect(['amount' => '249.51', 'method' => 'cash'])->assertUnprocessable()->assertJsonPath('code', 'AMOUNT_EXCEEDS_DUE');
        $collect(['amount' => '249.50', 'method' => 'nagad'])->assertCreated()->assertJsonPath('meta.customer.current_due', '0.00');
        $collect(['amount' => '1', 'method' => 'cash'])->assertUnprocessable()->assertJsonPath('code', 'AMOUNT_EXCEEDS_DUE');
        $collect(['amount' => '0', 'method' => 'cash'])->assertUnprocessable()->assertJsonValidationErrors('amount');
        $collect(['amount' => '10', 'method' => 'due'])->assertUnprocessable()->assertJsonValidationErrors('method');

        // The ledger tells the whole story, newest first, with a running balance.
        $ledger = $this->asOwnerOf($shop)->getJson("/api/v1/customers/{$customer->id}/ledger")->assertOk()->json('data');
        $this->assertSame(['payment', 'payment', 'payment', 'sale_due'], array_column($ledger, 'type'));
        $this->assertSame(['0.00', '249.50', '350.00', '600.00'], array_column($ledger, 'balance_after'));
        $this->assertSame(['nagad', 'bkash', 'cash', null], array_column($ledger, 'payment_method'));
        $this->assertSame('INV-000001', $ledger[3]['invoice_no']);

        $this->asOwnerOf($shop)->getJson("/api/v1/customers/{$customer->id}")
            ->assertJsonPath('data.current_due', '0.00')
            ->assertJsonPath('data.total_purchases', '1000.00')
            ->assertJsonPath('data.total_paid', '1000.00');

        $this->asOwnerOf($shop)->getJson("/api/v1/customers/{$customer->id}/payments")->assertOk()->assertJsonCount(4, 'data');
        $this->asOwnerOf($shop)->getJson("/api/v1/customers/{$customer->id}/sales")->assertOk()->assertJsonCount(1, 'data');
    }

    public function test_a_repeated_collection_request_is_recorded_once(): void
    {
        [$shop, $variant] = $this->shopWithItem();
        $customer = $this->customerIn($shop);
        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '1000', [
            'payments' => [], 'due_amount' => '1000', 'customer_id' => $customer->id,
        ]))->assertCreated();

        $request = ['client_uuid' => (string) Str::uuid(), 'amount' => '300', 'method' => 'cash'];

        $first = $this->asOwnerOf($shop)->postJson("/api/v1/customers/{$customer->id}/collect-due", $request)->assertCreated();
        $second = $this->asOwnerOf($shop)->postJson("/api/v1/customers/{$customer->id}/collect-due", $request)->assertOk();

        $this->assertSame($first->json('data.id'), $second->json('data.id'));
        $this->assertSame('700.00', $this->dueOf($customer));
    }

    public function test_the_ledger_balance_always_equals_the_sum_of_its_entries(): void
    {
        [$shop, $variant] = $this->shopWithItem('100');
        $customer = $this->customerIn($shop);
        $sell = fn (string $paid, string $due) => $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '100', [
            'payments' => $paid === '0' ? [] : [['method' => 'cash', 'amount' => $paid]], 'due_amount' => $due, 'customer_id' => $customer->id,
        ]))->assertCreated();
        $collect = fn (string $amount) => $this->asOwnerOf($shop)->postJson("/api/v1/customers/{$customer->id}/collect-due", [
            'client_uuid' => (string) Str::uuid(), 'amount' => $amount, 'method' => 'cash',
        ])->assertCreated();

        $sell('0', '100');
        $collect('33.33');
        $sell('40', '60');
        $collect('0.01');
        $sell('99.99', '0.01');
        $collect('66.67');

        $this->tenant()->runFor($shop, function () use ($customer) {
            $entries = CustomerLedger::query()->where('customer_id', $customer->id)->orderBy('id')->get();
            $running = '0.00';
            foreach ($entries as $entry) {
                $running = bcadd_or_brick($running, $entry->debit, $entry->credit);
                $this->assertSame($running, $entry->balance_after, 'Every entry carries the correct running balance.');
            }
            $this->assertSame($running, Customer::query()->findOrFail($customer->id)->current_due);
            $this->assertSame('60.00', $running); // 100 − 33.33 + 60 − 0.01 + 0.01 − 66.67
        });
    }

    // --- Customers themselves ----------------------------------------------------------

    public function test_customers_can_be_created_with_an_opening_due_searched_updated_and_deleted(): void
    {
        $shop = $this->createShop();

        $id = $this->asOwnerOf($shop)->postJson('/api/v1/customers', [
            'name' => 'Old Customer', 'phone' => '০১৭১২৩৪৫৬৭৮', 'address' => 'Mirpur', 'opening_due' => '750',
        ])->assertCreated()->assertJsonPath('data.phone', '01712345678')->assertJsonPath('data.current_due', '750.00')->json('data.id');

        // The opening balance is a ledger entry, not just a number.
        $this->asOwnerOf($shop)->getJson("/api/v1/customers/{$id}/ledger")->assertJsonPath('data.0.type', 'opening')->assertJsonPath('data.0.debit', '750.00');

        $this->asOwnerOf($shop)->postJson('/api/v1/customers', ['name' => 'Twin', 'phone' => '+8801712345678'])
            ->assertUnprocessable()->assertJsonPath('code', 'CUSTOMER_EXISTS');
        $this->asOwnerOf($shop)->postJson('/api/v1/customers', ['name' => '', 'phone' => '123'])
            ->assertUnprocessable()->assertJsonValidationErrors(['name', 'phone']);

        $other = $this->asOwnerOf($shop)->postJson('/api/v1/customers', ['name' => 'Second', 'phone' => '01812345678'])->json('data.id');

        $this->asOwnerOf($shop)->getJson('/api/v1/customers?q=old')->assertJsonCount(1, 'data');
        $this->asOwnerOf($shop)->getJson('/api/v1/customers?q=0171234')->assertJsonCount(1, 'data');
        $this->asOwnerOf($shop)->getJson('/api/v1/customers?has_due=1')->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $id);
        $this->asOwnerOf($shop)->getJson('/api/v1/customers')->assertJsonCount(2, 'data');

        $this->asOwnerOf($shop)->patchJson("/api/v1/customers/{$other}", ['name' => 'Renamed', 'phone' => '01712345678'])
            ->assertUnprocessable()->assertJsonValidationErrors('phone');
        // The balance cannot be edited directly.
        $this->asOwnerOf($shop)->patchJson("/api/v1/customers/{$id}", ['name' => 'Renamed', 'current_due' => '0', 'notes' => 'Pays monthly'])
            ->assertOk()->assertJsonPath('data.name', 'Renamed')->assertJsonPath('data.current_due', '750.00');

        $this->asOwnerOf($shop)->deleteJson("/api/v1/customers/{$id}")->assertConflict()->assertJsonPath('code', 'CUSTOMER_HAS_DUE');
        $this->asOwnerOf($shop)->deleteJson("/api/v1/customers/{$other}")->assertNoContent();

        // The deleted customer's number can be used again and brings their record back.
        $this->asOwnerOf($shop)->postJson('/api/v1/customers', ['name' => 'Second Again', 'phone' => '01812345678'])
            ->assertCreated()->assertJsonPath('data.id', $other);
    }

    public function test_a_cashier_can_collect_dues_and_manage_customers_but_a_role_without_permission_cannot(): void
    {
        [$shop] = $this->shopWithItem();
        $customer = $this->customerIn($shop);
        $cashier = $this->addMember($shop, ShopRole::Cashier);
        config(['dokani.roles.cashier' => ['shop.view', 'pos.sell']]);

        $this->asUser($cashier)->getJson('/api/v1/customers')->assertOk();
        $this->asUser($cashier)->postJson('/api/v1/customers', ['name' => 'X', 'phone' => '01712345678'])->assertForbidden();
        $this->asUser($cashier)->postJson("/api/v1/customers/{$customer->id}/collect-due", [
            'client_uuid' => (string) Str::uuid(), 'amount' => '1', 'method' => 'cash',
        ])->assertForbidden();
    }
}

/** Running balance with exact decimals: balance + debit − credit. */
function bcadd_or_brick(string $balance, string $debit, string $credit): string
{
    return Dec::money(Dec::of($balance)->plus($debit)->minus($credit));
}
