<?php

namespace Tests\Feature\Api;

use App\Enums\ShopRole;
use App\Models\Customer;
use App\Models\Device;
use App\Models\Plan;
use App\Models\ProductVariant;
use App\Models\Sale;
use App\Models\Shop;
use App\Models\ShopNotification;
use App\Models\User;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Offline mode, server side: what a phone pulls to work offline, and what
 * happens when it pushes sales and payments it recorded without a connection.
 */
class SyncTest extends TestCase
{
    private Shop $shop;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-03-10 06:00:00');
        $this->shop = $this->createShop();
    }

    private function pull(string $what, ?string $since = null, string $extra = ''): array
    {
        return $this->asOwnerOf($this->shop)
            ->getJson("/api/v1/sync/{$what}?".($since ? 'since='.urlencode($since) : '').$extra)
            ->assertOk()->json();
    }

    private function push(array $body, ?User $as = null): array
    {
        return ($as ? $this->asUser($as) : $this->asOwnerOf($this->shop))
            ->postJson('/api/v1/sync/push', $body)->assertOk()->json('data');
    }

    /** An offline sale as the phone queues it: always with the price it showed. */
    private function offlineSale(int $variantId, $quantity, string $unitPrice, string $total, array $overrides = []): array
    {
        return $this->salePayload([[$variantId, $quantity, ['unit_price' => $unitPrice]]], $total, $overrides + [
            'offline_ref' => 'OFF-'.strtoupper(Str::random(6)),
            'sold_at' => now()->subHours(2)->toIso8601String(),
        ]);
    }

    private function stockOf(int $variantId): string
    {
        return $this->tenant()->withoutTenancy(fn () => ProductVariant::query()->withTrashed()->whereKey($variantId)->value('stock_quantity'));
    }

    // --- Pull ---------------------------------------------------------------------

    public function test_the_first_sync_downloads_the_whole_catalogue_with_barcodes(): void
    {
        $this->createProduct($this->shop, ['name' => 'Lux Soap'], [['purchase_price' => 38, 'selling_price' => 45, 'stock_quantity' => 20, 'barcodes' => ['SOAP-1', 'SOAP-2']]]);
        $this->createProduct($this->shop, ['name' => 'Polo'], [
            ['name' => 'S', 'purchase_price' => 200, 'selling_price' => 350, 'stock_quantity' => 4, 'barcodes' => ['TS-S']],
            ['name' => 'M', 'purchase_price' => 210, 'selling_price' => 370, 'stock_quantity' => 6],
        ]);
        $deleted = $this->createProduct($this->shop, ['name' => 'Deleted before first sync']);
        $this->asOwnerOf($this->shop)->deleteJson("/api/v1/products/{$deleted->id}")->assertNoContent();

        $response = $this->pull('products');

        $this->assertSame(['Lux Soap', 'Polo'], array_column($response['data'], 'name'));
        $this->assertSame(['SOAP-1', 'SOAP-2'], $response['data'][0]['variants'][0]['barcodes']);
        $this->assertSame('45.00', $response['data'][0]['variants'][0]['selling_price']);
        $this->assertSame('20.000', $response['data'][0]['variants'][0]['stock_quantity']);
        $this->assertCount(2, $response['data'][1]['variants']);
        $this->assertSame([], $response['deleted_ids'], 'A first sync has nothing to forget.');
        $this->assertSame(1, $response['meta']['last_page']);
        $this->assertNotEmpty($response['meta']['cursor']);
    }

    public function test_later_syncs_send_only_what_changed_including_stock_barcodes_and_deletions(): void
    {
        $soap = $this->createProduct($this->shop, ['name' => 'Soap'], [['purchase_price' => 38, 'selling_price' => 45, 'stock_quantity' => 20]]);
        $rice = $this->createProduct($this->shop, ['name' => 'Rice']);
        $sugar = $this->createProduct($this->shop, ['name' => 'Sugar']);
        $salt = $this->createProduct($this->shop, ['name' => 'Salt']);
        $untouched = $this->createProduct($this->shop, ['name' => 'Untouched']);

        $this->travel(1)->minutes();
        $cursor = $this->pull('products')['meta']['cursor'];
        $this->travel(10)->minutes();

        // Nothing changed yet.
        $this->assertSame([], $this->pull('products', $cursor)['data']);

        // 1. stock changes through a sale (touches only the variant row)
        $this->asOwnerOf($this->shop)->postJson('/api/v1/sales', $this->salePayload([[$soap->variants[0]->id, 3]], '135'))->assertCreated();
        // 2. only a barcode is added
        $this->asOwnerOf($this->shop)->patchJson("/api/v1/products/{$rice->id}", [
            'variants' => [['id' => $rice->variants[0]->id, 'purchase_price' => 50, 'selling_price' => 60, 'barcodes' => ['NEW-CODE']]],
        ])->assertOk();
        // 3. a price change
        $this->asOwnerOf($this->shop)->patchJson("/api/v1/products/{$sugar->id}", [
            'variants' => [['id' => $sugar->variants[0]->id, 'purchase_price' => 50, 'selling_price' => 75]],
        ])->assertOk();
        // 4. a deletion
        $this->asOwnerOf($this->shop)->deleteJson("/api/v1/products/{$salt->id}")->assertNoContent();

        $delta = $this->pull('products', $cursor);
        $byName = collect($delta['data'])->keyBy('name');

        $this->assertEqualsCanonicalizing(['Soap', 'Rice', 'Sugar'], $byName->keys()->all());
        $this->assertSame('17.000', $byName['Soap']['variants'][0]['stock_quantity']);
        $this->assertSame(['NEW-CODE'], $byName['Rice']['variants'][0]['barcodes']);
        $this->assertSame('75.00', $byName['Sugar']['variants'][0]['selling_price']);
        $this->assertSame([$salt->id], $delta['deleted_ids']);
        $this->assertNotContains($untouched->name, $byName->keys()->all());
    }

    public function test_a_change_made_during_a_sync_is_sent_again_next_time_rather_than_missed(): void
    {
        $product = $this->createProduct($this->shop);
        $cursor = $this->pull('products')['meta']['cursor'];

        // Saved in the same second the cursor was issued.
        $this->asOwnerOf($this->shop)->patchJson("/api/v1/products/{$product->id}", ['name' => 'Changed at the same moment'])->assertOk();

        $this->assertSame(['Changed at the same moment'], array_column($this->pull('products', $cursor)['data'], 'name'));
    }

    public function test_the_catalogue_is_sent_in_pages(): void
    {
        foreach (range(1, 5) as $i) {
            $this->createProduct($this->shop, ['name' => "Item {$i}"]);
        }

        $page1 = $this->pull('products', null, 'page=1&per_page=2');
        $this->assertSame(1, $page1['meta']['last_page'], 'The page size is fixed by the server.');
        $this->assertCount(5, $page1['data']);
    }

    public function test_customers_and_categories_sync_the_same_way(): void
    {
        $karim = $this->tenant()->runFor($this->shop, fn () => Customer::factory()->create(['name' => 'Karim']));
        $gone = $this->tenant()->runFor($this->shop, fn () => Customer::factory()->create(['name' => 'Gone']));
        $categoryId = $this->asOwnerOf($this->shop)->postJson('/api/v1/categories', ['name' => 'Snacks'])->json('data.id');

        $first = $this->pull('customers');
        $this->assertEqualsCanonicalizing(['Karim', 'Gone'], array_column($first['data'], 'name'));
        $this->assertSame(['Snacks'], array_column($this->pull('categories')['data'], 'name'));

        $cursor = $first['meta']['cursor'];
        $this->travel(10)->minutes();

        // A due sale changes the customer's balance; another customer is deleted; the category is renamed.
        $variant = $this->createProduct($this->shop)->variants[0];
        $this->asOwnerOf($this->shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '60', [
            'payments' => [], 'due_amount' => '60', 'customer_id' => $karim->id,
        ]))->assertCreated();
        $this->asOwnerOf($this->shop)->deleteJson("/api/v1/customers/{$gone->id}")->assertNoContent();
        $this->asOwnerOf($this->shop)->patchJson("/api/v1/categories/{$categoryId}", ['name' => 'Snacks & Drinks'])->assertOk();

        $customers = $this->pull('customers', $cursor);
        $this->assertSame(['Karim'], array_column($customers['data'], 'name'));
        $this->assertSame('60.00', $customers['data'][0]['current_due']);
        $this->assertSame([$gone->id], $customers['deleted_ids']);

        $this->assertSame(['Snacks & Drinks'], array_column($this->pull('categories', $cursor)['data'], 'name'));
    }

    public function test_a_phone_only_ever_receives_its_own_shops_data(): void
    {
        $this->createProduct($this->shop, ['name' => 'Mine']);
        $other = $this->createShop();
        $this->createProduct($other, ['name' => 'Theirs'], [['purchase_price' => 1, 'selling_price' => 2, 'barcodes' => ['THEIR-CODE']]]);
        $this->tenant()->runFor($other, fn () => Customer::factory()->create(['name' => 'Their Customer']));

        $this->assertSame(['Mine'], array_column($this->pull('products')['data'], 'name'));
        $this->assertSame([], $this->pull('customers')['data']);
        $this->assertStringNotContainsString('THEIR-CODE', json_encode($this->pull('products')));

        // The other shop's later changes never appear in this shop's delta either.
        $this->travel(1)->minutes();
        $cursor = $this->pull('products')['meta']['cursor'];
        $this->travel(1)->minutes();
        $this->createProduct($other, ['name' => 'Their new product']);
        $this->assertSame([], $this->pull('products', $cursor)['data']);
    }

    // --- Push: sales -------------------------------------------------------------------

    public function test_an_offline_sale_is_stored_with_the_time_and_price_from_the_phone(): void
    {
        $product = $this->createProduct($this->shop); // price 60, stock 10
        $variant = $product->variants[0];
        $soldAt = now()->subHours(5);
        $sale = $this->offlineSale($variant->id, 2, '60.00', '120', ['sold_at' => $soldAt->toIso8601String(), 'offline_ref' => 'OFF-A1-0007']);

        // The owner raises the price before the phone comes back online.
        $this->asOwnerOf($this->shop)->patchJson("/api/v1/products/{$product->id}", [
            'variants' => [['id' => $variant->id, 'purchase_price' => 50, 'selling_price' => 75]],
        ])->assertOk();

        $cashier = $this->addMember($this->shop, ShopRole::Cashier);
        $result = $this->push(['sales' => [$sale]], $cashier)['sales'][0];

        $this->assertSame('created', $result['status']);
        $this->assertSame($sale['client_uuid'], $result['client_uuid']);
        $this->assertSame('INV-000001', $result['server']['invoice_no']);
        $this->assertFalse($result['server']['has_stock_conflict']);
        $this->assertMatchesRegularExpression('#/i/[A-Za-z0-9_-]{43}$#', $result['server']['invoice_url']);

        $this->asOwnerOf($this->shop)->getJson("/api/v1/sales/{$result['server']['id']}")->assertOk()
            ->assertJsonPath('data.source', 'offline')
            ->assertJsonPath('data.offline_ref', 'OFF-A1-0007')
            ->assertJsonPath('data.grand_total', '120.00')
            // What the customer actually paid, not today's price — even though a cashier cannot override prices online.
            ->assertJsonPath('data.items.0.unit_price', '60.00')
            ->assertJsonPath('data.sold_at', $soldAt->toIso8601String());

        $this->assertSame('8.000', $this->stockOf($variant->id));
    }

    public function test_pushing_the_same_sale_again_is_harmless(): void
    {
        $variant = $this->createProduct($this->shop)->variants[0];
        $sale = $this->offlineSale($variant->id, 2, '60', '120');

        $first = $this->push(['sales' => [$sale]])['sales'][0];
        // The answer was lost on a bad connection, so the phone sends it again.
        $second = $this->push(['sales' => [$sale]])['sales'][0];
        $third = $this->push(['sales' => [$sale]])['sales'][0];

        $this->assertSame('created', $first['status']);
        $this->assertSame('duplicate', $second['status']);
        $this->assertSame('duplicate', $third['status']);
        $this->assertSame($first['server']['id'], $second['server']['id']);
        $this->assertSame($first['server']['invoice_no'], $third['server']['invoice_no']);

        $this->assertSame('8.000', $this->stockOf($variant->id), 'Stock is deducted once.');
        $this->tenant()->runFor($this->shop, fn () => $this->assertSame(1, Sale::query()->count()));
    }

    public function test_a_sale_already_sent_online_is_recognised_when_it_arrives_again_through_sync(): void
    {
        $variant = $this->createProduct($this->shop)->variants[0];
        $sale = $this->offlineSale($variant->id, 1, '60', '60');

        // The online request reached the server, but the phone never saw the answer and queued the sale.
        $online = $this->asOwnerOf($this->shop)->postJson('/api/v1/sales', $sale)->assertCreated()->json('data.id');
        $result = $this->push(['sales' => [$sale]])['sales'][0];

        $this->assertSame('duplicate', $result['status']);
        $this->assertSame($online, $result['server']['id']);
        $this->assertSame('9.000', $this->stockOf($variant->id));
    }

    public function test_an_offline_sale_beyond_the_stock_is_accepted_flagged_and_reported_to_the_owner(): void
    {
        $variant = $this->createProduct($this->shop, ['name' => 'Lux Soap'], [['purchase_price' => 38, 'selling_price' => 45, 'stock_quantity' => 2]])->variants[0];

        // Meanwhile another phone sold the last two online.
        $this->asOwnerOf($this->shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 2]], '90'))->assertCreated();

        $result = $this->push(['sales' => [$this->offlineSale($variant->id, 3, '45', '135')]])['sales'][0];

        // The goods already left the shop: the sale is recorded, never refused.
        $this->assertSame('created', $result['status']);
        $this->assertTrue($result['server']['has_stock_conflict']);
        $this->assertSame('-3.000', $this->stockOf($variant->id));

        $this->asOwnerOf($this->shop)->getJson('/api/v1/notifications?unread=1')->assertOk()
            ->assertJsonPath('meta.unread', 1)
            ->assertJsonPath('data.0.type', 'stock_conflict')
            ->assertJsonPath('data.0.data.invoice_no', $result['server']['invoice_no'])
            ->assertJsonPath('data.0.data.products', ['Lux Soap']);

        // The owner corrects the count and clears the notice.
        $this->asOwnerOf($this->shop)->postJson('/api/v1/stock/adjust', ['variant_id' => $variant->id, 'new_quantity' => 0])->assertCreated();
        $id = $this->tenant()->runFor($this->shop, fn () => ShopNotification::query()->value('id'));
        $this->asOwnerOf($this->shop)->postJson("/api/v1/notifications/{$id}/read")->assertNoContent();
        $this->asOwnerOf($this->shop)->getJson('/api/v1/notifications')->assertJsonPath('meta.unread', 0)->assertJsonPath('data.0.read', true);
    }

    public function test_an_offline_sale_of_a_product_deleted_since_is_still_recorded(): void
    {
        $product = $this->createProduct($this->shop, ['name' => 'Discontinued']);
        $variant = $product->variants[0];
        $this->asOwnerOf($this->shop)->deleteJson("/api/v1/products/{$product->id}")->assertNoContent();

        $result = $this->push(['sales' => [$this->offlineSale($variant->id, 1, '60', '60')]])['sales'][0];

        $this->assertSame('created', $result['status']);
        $this->asOwnerOf($this->shop)->getJson("/api/v1/sales/{$result['server']['id']}")->assertJsonPath('data.items.0.product_name', 'Discontinued');
        $this->assertSame('9.000', $this->stockOf($variant->id));
    }

    public function test_an_offline_due_sale_keeps_the_customer_and_reaches_the_ledger(): void
    {
        $variant = $this->createProduct($this->shop, [], [['purchase_price' => 700, 'selling_price' => 1000, 'stock_quantity' => 5]])->variants[0];

        $result = $this->push(['sales' => [$this->offlineSale($variant->id, 1, '1000', '1000', [
            'payments' => [['method' => 'cash', 'amount' => '600'], ['method' => 'bkash', 'amount' => '100', 'transaction_id' => 'TX5']],
            'due_amount' => '300',
            'customer' => ['name' => 'Rahim Uddin', 'phone' => '+880 1712-345678'],
        ])]])['sales'][0];

        $this->assertSame('created', $result['status']);

        $this->tenant()->runFor($this->shop, function () use ($result) {
            $customer = Customer::query()->sole();
            $this->assertSame('Rahim Uddin', $customer->name);
            $this->assertSame('01712345678', $customer->phone);
            $this->assertSame('300.00', $customer->current_due);
            $this->assertSame($result['server']['id'], $customer->ledger()->sole()->sale_id);
            $this->assertSame(['cash', 'bkash'], Sale::query()->sole()->payments->pluck('method')->map->value->all());
        });
    }

    public function test_offline_sales_ignore_limits_that_only_make_sense_before_a_sale(): void
    {
        Plan::query()->where('code', 'free')->update(['max_monthly_sales' => 1]);
        $variant = $this->createProduct($this->shop, [], [['purchase_price' => 50, 'selling_price' => 100, 'stock_quantity' => 50]])->variants[0];
        $customer = $this->tenant()->runFor($this->shop, fn () => Customer::factory()->create(['credit_limit' => '50']));

        $this->asOwnerOf($this->shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '100'))->assertCreated();
        $this->asOwnerOf($this->shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '100'))->assertForbidden();

        // Over the monthly limit and over the customer's credit limit — but it already happened.
        $result = $this->push(['sales' => [$this->offlineSale($variant->id, 2, '100', '200', [
            'payments' => [], 'due_amount' => '200', 'customer_id' => $customer->id,
        ])]])['sales'][0];

        $this->assertSame('created', $result['status']);
    }

    public function test_arithmetic_that_does_not_add_up_is_reported_back_not_stored_and_not_lost(): void
    {
        $variant = $this->createProduct($this->shop)->variants[0];

        $wrongTotal = $this->offlineSale($variant->id, 2, '60', '100');
        $noCustomer = $this->offlineSale($variant->id, 1, '60', '60', ['payments' => [], 'due_amount' => '60']);
        $unknown = $this->offlineSale(999999, 1, '60', '60');
        $malformed = ['client_uuid' => (string) Str::uuid(), 'items' => []];
        $good = $this->offlineSale($variant->id, 1, '60', '60');

        $results = $this->push(['sales' => [$wrongTotal, $noCustomer, $unknown, $malformed, 'not even an object', $good]])['sales'];

        $this->assertSame(['failed', 'failed', 'failed', 'failed', 'failed', 'created'], array_column($results, 'status'));
        $this->assertSame(['TOTALS_MISMATCH', 'DUE_REQUIRES_CUSTOMER', 'PRODUCT_UNAVAILABLE', 'VALIDATION_FAILED', 'VALIDATION_FAILED'], array_slice(array_column($results, 'code'), 0, 5));

        // Each failure names its record and says why, so the phone can show it.
        $this->assertSame($wrongTotal['client_uuid'], $results[0]['client_uuid']);
        $this->assertNotEmpty($results[0]['message']);
        $this->assertNull($results[4]['client_uuid']);

        // One bad record does not block the good one that followed, and stores nothing itself.
        $this->tenant()->runFor($this->shop, fn () => $this->assertSame(1, Sale::query()->count()));
        $this->assertSame('9.000', $this->stockOf($variant->id));
    }

    public function test_an_offline_sale_cannot_reach_into_another_shop(): void
    {
        $other = $this->createShop();
        $foreign = $this->createProduct($other)->variants[0];
        $foreignCustomer = $this->tenant()->runFor($other, fn () => Customer::factory()->create());
        $mine = $this->createProduct($this->shop)->variants[0];

        $results = $this->push(['sales' => [
            $this->offlineSale($foreign->id, 1, '60', '60'),
            $this->offlineSale($mine->id, 1, '60', '60', ['payments' => [], 'due_amount' => '60', 'customer_id' => $foreignCustomer->id]),
        ]])['sales'];

        $this->assertSame(['failed', 'failed'], array_column($results, 'status'));
        $this->assertSame('10.000', $this->stockOf($foreign->id));
        $this->assertSame('0.00', $this->tenant()->withoutTenancy(fn () => Customer::query()->whereKey($foreignCustomer->id)->value('current_due')));
        $this->tenant()->withoutTenancy(fn () => $this->assertSame(0, Sale::query()->count()));
    }

    // --- Push: due collections ----------------------------------------------------------

    public function test_offline_due_collections_follow_the_sales_in_the_same_push(): void
    {
        $variant = $this->createProduct($this->shop, [], [['purchase_price' => 700, 'selling_price' => 1000, 'stock_quantity' => 5]])->variants[0];
        $existing = $this->tenant()->runFor($this->shop, fn () => Customer::factory()->create());
        $this->asOwnerOf($this->shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '1000', [
            'payments' => [], 'due_amount' => '1000', 'customer_id' => $existing->id,
        ]))->assertCreated();

        $paidAt = now()->subHours(3);
        $data = $this->push([
            // A new customer buys on due offline…
            'sales' => [$this->offlineSale($variant->id, 1, '1000', '1000', [
                'payments' => [], 'due_amount' => '1000', 'customer' => ['name' => 'New Offline Customer', 'phone' => '01999999999'],
            ])],
            'due_collections' => [
                // …and pays part of it back before the phone syncs (known only by phone number).
                ['client_uuid' => (string) Str::uuid(), 'customer_phone' => '01999999999', 'amount' => '400', 'method' => 'cash', 'paid_at' => $paidAt->toIso8601String()],
                // An existing customer pays by bKash.
                ['client_uuid' => (string) Str::uuid(), 'customer_id' => $existing->id, 'amount' => '250', 'method' => 'bkash', 'transaction_id' => 'TX9'],
            ],
        ]);

        $this->assertSame(['created'], array_column($data['sales'], 'status'));
        $this->assertSame(['created', 'created'], array_column($data['due_collections'], 'status'));
        $this->assertSame('600.00', $data['due_collections'][0]['server']['current_due']);
        $this->assertSame('750.00', $data['due_collections'][1]['server']['current_due']);

        $this->tenant()->runFor($this->shop, function () use ($paidAt) {
            $new = Customer::query()->where('phone', '01999999999')->sole();
            $this->assertSame(['sale_due', 'payment'], $new->ledger()->orderBy('id')->pluck('type')->map->value->all());
            $this->assertTrue($new->payments()->where('type', 'due_collection')->sole()->paid_at->equalTo($paidAt), 'Recorded at the time the money was received.');
        });
    }

    public function test_a_repeated_offline_collection_is_recorded_once(): void
    {
        $customer = $this->tenant()->runFor($this->shop, fn () => Customer::factory()->create());
        $this->asOwnerOf($this->shop)->postJson('/api/v1/customers', ['name' => 'X', 'phone' => '01712345678', 'opening_due' => '500'])->assertCreated();
        $collection = ['client_uuid' => (string) Str::uuid(), 'customer_phone' => '01712345678', 'amount' => '200', 'method' => 'cash'];

        $first = $this->push(['due_collections' => [$collection]])['due_collections'][0];
        $second = $this->push(['due_collections' => [$collection]])['due_collections'][0];

        $this->assertSame(['created', 'duplicate'], [$first['status'], $second['status']]);
        $this->assertSame('300.00', $second['server']['current_due']);
        $this->assertNotNull($customer);
    }

    public function test_money_collected_offline_is_recorded_even_if_it_is_more_than_the_server_thinks_is_owed(): void
    {
        $id = $this->asOwnerOf($this->shop)->postJson('/api/v1/customers', ['name' => 'X', 'phone' => '01712345678', 'opening_due' => '500'])->json('data.id');

        // Another phone already collected 400 online; this phone, offline, collected 300 of what it believed was 500.
        $this->asOwnerOf($this->shop)->postJson("/api/v1/customers/{$id}/collect-due", ['client_uuid' => (string) Str::uuid(), 'amount' => '400', 'method' => 'cash'])->assertCreated();

        $result = $this->push(['due_collections' => [
            ['client_uuid' => (string) Str::uuid(), 'customer_id' => $id, 'amount' => '300', 'method' => 'cash'],
        ]])['due_collections'][0];

        // The cash is in the drawer, so it is on the books: the customer is now 200 in credit.
        $this->assertSame('created', $result['status']);
        $this->assertSame('-200.00', $result['server']['current_due']);
    }

    public function test_a_collection_for_an_unknown_customer_is_reported_as_failed(): void
    {
        $results = $this->push(['due_collections' => [
            ['client_uuid' => (string) Str::uuid(), 'customer_phone' => '01999999999', 'amount' => '10', 'method' => 'cash'],
            ['client_uuid' => (string) Str::uuid(), 'customer_id' => 999999, 'amount' => '10', 'method' => 'cash'],
            ['client_uuid' => (string) Str::uuid(), 'amount' => '10', 'method' => 'cash'],
        ]])['due_collections'];

        $this->assertSame(['failed', 'failed', 'failed'], array_column($results, 'status'));
        $this->assertSame(['CUSTOMER_NOT_FOUND', 'CUSTOMER_NOT_FOUND', 'VALIDATION_FAILED'], array_column($results, 'code'));
    }

    // --- Push: access and devices --------------------------------------------------------

    public function test_roles_are_respected_when_syncing(): void
    {
        $variant = $this->createProduct($this->shop)->variants[0];
        $this->asOwnerOf($this->shop)->postJson('/api/v1/customers', ['name' => 'X', 'phone' => '01712345678', 'opening_due' => '500'])->assertCreated();
        $viewer = $this->addMember($this->shop, ShopRole::Cashier);
        config(['dokani.roles.cashier' => ['shop.view']]);

        $data = $this->push([
            'sales' => [$this->offlineSale($variant->id, 1, '60', '60')],
            'due_collections' => [['client_uuid' => (string) Str::uuid(), 'customer_phone' => '01712345678', 'amount' => '10', 'method' => 'cash']],
        ], $viewer);

        $this->assertSame(['FORBIDDEN'], array_column($data['sales'], 'code'));
        $this->assertSame(['FORBIDDEN'], array_column($data['due_collections'], 'code'));
        $this->assertSame('10.000', $this->stockOf($variant->id));
    }

    public function test_a_suspended_shop_cannot_sync_and_nothing_is_stored_until_it_is_restored(): void
    {
        $variant = $this->createProduct($this->shop)->variants[0];
        $sale = $this->offlineSale($variant->id, 1, '60', '60');

        $this->shop->forceFill(['status' => 'suspended'])->save();
        $this->asOwnerOf($this->shop)->postJson('/api/v1/sync/push', ['sales' => [$sale]])->assertForbidden()->assertJsonPath('code', 'SHOP_SUSPENDED');
        $this->asOwnerOf($this->shop)->getJson('/api/v1/sync/products')->assertForbidden();
        $this->tenant()->runFor($this->shop, fn () => $this->assertSame(0, Sale::query()->count()));

        // The phone kept the sale; once the shop is restored the same push goes through.
        $this->shop->forceFill(['status' => 'active'])->save();
        $this->assertSame('created', $this->push(['sales' => [$sale]])['sales'][0]['status']);
    }

    public function test_a_push_is_limited_to_small_batches(): void
    {
        $this->asOwnerOf($this->shop)->postJson('/api/v1/sync/push', ['sales' => array_fill(0, 51, [])])
            ->assertUnprocessable()->assertJsonValidationErrors('sales');
        $this->assertSame(['sales' => [], 'due_collections' => []], $this->push([]));
    }

    public function test_the_phone_is_registered_and_its_sales_are_attributed_to_it(): void
    {
        $variant = $this->createProduct($this->shop)->variants[0];
        $uuid = (string) Str::uuid();

        $this->asOwnerOf($this->shop)->postJson('/api/v1/devices', ['uuid' => $uuid, 'name' => 'Pixel 4a', 'platform' => 'android', 'app_version' => '0.1.0'])
            ->assertOk()->assertJsonPath('data.uuid', $uuid);

        $result = $this->push(['device' => ['uuid' => $uuid], 'sales' => [$this->offlineSale($variant->id, 1, '60', '60')]])['sales'][0];

        $this->tenant()->runFor($this->shop, function () use ($uuid, $result) {
            $device = Device::query()->sole(); // registered once, not twice
            $this->assertSame($uuid, $device->device_uuid);
            $this->assertSame('Pixel 4a', $device->name);
            $this->assertNotNull($device->last_synced_at);
            $this->assertSame($device->id, Sale::query()->findOrFail($result['server']['id'])->device_id);
        });
    }

    public function test_notifications_belong_to_one_shop(): void
    {
        $other = $this->createShop();
        $theirs = $this->tenant()->runFor($other, fn () => ShopNotification::create(['type' => 'stock_conflict', 'title' => 'Theirs']));

        $this->asOwnerOf($this->shop)->getJson('/api/v1/notifications')->assertOk()->assertJsonCount(0, 'data')->assertJsonPath('meta.unread', 0);
        $this->asOwnerOf($this->shop)->postJson("/api/v1/notifications/{$theirs->id}/read")->assertNotFound();
        $this->asOwnerOf($this->shop)->postJson('/api/v1/notifications/read-all')->assertNoContent();

        $this->assertNull($this->tenant()->withoutTenancy(fn () => ShopNotification::query()->findOrFail($theirs->id))->read_at);
    }
}
