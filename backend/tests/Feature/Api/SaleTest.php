<?php

namespace Tests\Feature\Api;

use App\Enums\ShopRole;
use App\Models\Customer;
use App\Models\Invoice;
use App\Models\Payment;
use App\Models\Plan;
use App\Models\ProductVariant;
use App\Models\Sale;
use App\Models\StockMovement;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class SaleTest extends TestCase
{
    private function stockOf(int $variantId): string
    {
        return $this->tenant()->withoutTenancy(fn () => ProductVariant::query()->withTrashed()->whereKey($variantId)->value('stock_quantity'));
    }

    // --- The basic sale ---------------------------------------------------------

    public function test_a_cash_sale_records_everything_and_needs_no_customer(): void
    {
        $shop = $this->createShop();
        $soap = $this->createProduct($shop, ['name' => 'Lux Soap'], [['purchase_price' => '38', 'selling_price' => '45', 'stock_quantity' => '20']]);
        $rice = $this->createProduct($shop, ['name' => 'Rice', 'unit_id' => $this->unitId('Kilogram')], [['purchase_price' => '62.50', 'selling_price' => '70', 'stock_quantity' => '50']]);

        $response = $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload(
            [[$soap->variants[0]->id, 2], [$rice->variants[0]->id, '1.5']],
            '195.00',
            ['payments' => [['method' => 'cash', 'amount' => '195', 'received_amount' => '200']]],
        ));

        $response->assertCreated()
            ->assertJsonPath('data.invoice_no', 'INV-000001')
            ->assertJsonPath('data.status', 'completed')
            ->assertJsonPath('data.subtotal', '195.00')        // 2×45 + 1.5×70
            ->assertJsonPath('data.grand_total', '195.00')
            ->assertJsonPath('data.paid_amount', '195.00')
            ->assertJsonPath('data.due_amount', '0.00')
            ->assertJsonPath('data.change_amount', '5.00')
            ->assertJsonPath('data.total_items', '3.500')
            ->assertJsonPath('data.total_cost', '169.75')      // 2×38 + 1.5×62.50
            ->assertJsonPath('data.gross_profit', '25.25')
            ->assertJsonPath('data.customer', null)
            ->assertJsonCount(2, 'data.items')
            ->assertJsonPath('data.items.0.product_name', 'Lux Soap')
            ->assertJsonPath('data.items.0.line_total', '90.00')
            ->assertJsonPath('data.items.1.unit_name', 'Kilogram')
            ->assertJsonPath('data.items.1.line_total', '105.00')
            ->assertJsonPath('data.payments.0.method', 'cash')
            ->assertJsonPath('data.payments.0.amount', '195.00')
            ->assertJsonPath('data.payments.0.received_amount', '200.00')
            ->assertJsonPath('data.payments.0.verification', 'unverified');

        // Stock went down, with a movement pointing at the sale.
        $this->assertSame('18.000', $this->stockOf($soap->variants[0]->id));
        $this->assertSame('48.500', $this->stockOf($rice->variants[0]->id));

        $this->tenant()->runFor($shop, function () use ($response, $soap) {
            $movement = StockMovement::query()->where('type', 'sale')->where('product_variant_id', $soap->variants[0]->id)->sole();
            $this->assertSame('-2.000', $movement->quantity);
            $this->assertSame('18.000', $movement->balance_after);
            $this->assertSame($response->json('data.id'), $movement->reference_id);

            $this->assertSame(0, Customer::query()->count(), 'A walk-in cash sale creates no customer.');
            $this->assertSame(1, Invoice::query()->count());
        });

        $this->assertMatchesRegularExpression('#/i/[A-Za-z0-9_-]{43}$#', $response->json('data.invoice_url'));
    }

    public function test_the_example_from_the_brief_adds_up(): void
    {
        // Subtotal 1,200 − discount 100 + charge 20 = 1,120
        $shop = $this->createShop();
        $item = $this->createProduct($shop, [], [['purchase_price' => '400', 'selling_price' => '600', 'stock_quantity' => '5']]);

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload(
            [[$item->variants[0]->id, 2]], '1120',
            ['discount_amount' => '100', 'additional_charge' => '20'],
        ))->assertCreated()
            ->assertJsonPath('data.subtotal', '1200.00')
            ->assertJsonPath('data.discount_amount', '100.00')
            ->assertJsonPath('data.additional_charge', '20.00')
            ->assertJsonPath('data.grand_total', '1120.00')
            // Profit is on the goods: 1,200 − 100 discount − 800 cost. The charge is not product profit.
            ->assertJsonPath('data.gross_profit', '300.00');
    }

    public function test_invoice_numbers_are_sequential_per_shop(): void
    {
        $a = $this->createShop();
        $b = $this->createShop();
        $va = $this->createProduct($a)->variants[0];
        $vb = $this->createProduct($b)->variants[0];

        $number = fn ($shop, $variant) => $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '60'))->json('data.invoice_no');

        $this->assertSame('INV-000001', $number($a, $va));
        $this->assertSame('INV-000002', $number($a, $va));
        $this->assertSame('INV-000001', $number($b, $vb), 'Each shop has its own sequence.');
        $this->assertSame('INV-000003', $number($a, $va));
    }

    public function test_a_rejected_sale_does_not_use_up_an_invoice_number_or_leave_anything_behind(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop)->variants[0];

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 999]], '59940'))->assertConflict();
        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '61'))->assertUnprocessable();

        $this->tenant()->runFor($shop, function () {
            $this->assertSame(0, Sale::query()->count());
            $this->assertSame(0, Payment::query()->count());
            $this->assertSame(0, StockMovement::query()->where('type', 'sale')->count());
        });
        $this->assertSame('10.000', $this->stockOf($variant->id));

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '60'))
            ->assertCreated()->assertJsonPath('data.invoice_no', 'INV-000001');
    }

    // --- The server does the arithmetic ------------------------------------------

    public function test_a_total_that_disagrees_with_the_servers_is_rejected(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop)->variants[0]; // price 60

        foreach (['119.99', '120.01', '1'] as $wrong) {
            $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 2]], $wrong))
                ->assertUnprocessable()->assertJsonPath('code', 'TOTALS_MISMATCH')
                ->assertJsonPath('errors.grand_total.0', '120.00');
        }
    }

    public function test_the_price_comes_from_the_server_not_from_the_app(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop)->variants[0]; // price 60
        $cashier = $this->addMember($shop, ShopRole::Cashier);

        // A cashier's app claiming a lower price is refused outright.
        $this->asUser($cashier)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1, ['unit_price' => '1']]], '1'))
            ->assertForbidden()->assertJsonPath('code', 'PRICE_OVERRIDE_NOT_ALLOWED');

        // Sending the real price explicitly is fine.
        $this->asUser($cashier)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1, ['unit_price' => '60.00']]], '60'))->assertCreated();

        // The owner may sell at a negotiated price; it is audited.
        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1, ['unit_price' => '55']]], '55'))
            ->assertCreated()->assertJsonPath('data.items.0.unit_price', '55.00');
        $this->assertDatabaseHas('audit_logs', ['shop_id' => $shop->id, 'action' => 'sale.price_overridden']);
    }

    public function test_a_stale_price_on_the_app_is_caught(): void
    {
        $shop = $this->createShop();
        $product = $this->createProduct($shop);
        $variant = $product->variants[0];
        $cashier = $this->addMember($shop, ShopRole::Cashier);

        // The owner raises the price after the cashier's app loaded the old one.
        $this->asOwnerOf($shop)->patchJson("/api/v1/products/{$product->id}", [
            'variants' => [['id' => $variant->id, 'purchase_price' => 50, 'selling_price' => 75]],
        ])->assertOk();

        $this->asUser($cashier)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '60'))
            ->assertUnprocessable()->assertJsonPath('code', 'TOTALS_MISMATCH')->assertJsonPath('errors.grand_total.0', '75.00');
    }

    public function test_discounts_cannot_exceed_what_they_apply_to(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop)->variants[0];

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1, ['discount_amount' => '61']]], '0', ['payments' => []]))
            ->assertUnprocessable()->assertJsonPath('code', 'DISCOUNT_TOO_LARGE');
        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '0', ['discount_amount' => '60.01', 'payments' => []]))
            ->assertUnprocessable()->assertJsonPath('code', 'DISCOUNT_TOO_LARGE');

        // Line and sale discounts together.
        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 2, ['discount_amount' => '10']]], '100', ['discount_amount' => '10']))
            ->assertCreated()
            ->assertJsonPath('data.items.0.line_total', '110.00')
            ->assertJsonPath('data.subtotal', '110.00')
            ->assertJsonPath('data.grand_total', '100.00');
    }

    public function test_line_amounts_are_rounded_half_up_per_line(): void
    {
        $shop = $this->createShop();
        $kg = $this->unitId('Kilogram');
        $a = $this->createProduct($shop, ['unit_id' => $kg], [['purchase_price' => '10.01', 'selling_price' => '33.33', 'stock_quantity' => '10']])->variants[0];
        $b = $this->createProduct($shop, ['unit_id' => $kg], [['purchase_price' => '0', 'selling_price' => '0.05', 'stock_quantity' => '10']])->variants[0];

        // 33.33 × 0.335 = 11.165550 → 11.17 ; 0.05 × 0.5 = 0.025 → 0.03 ; cost 10.01 × 0.335 = 3.35335 → 3.35
        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$a->id, '0.335'], [$b->id, '0.5']], '11.20'))
            ->assertCreated()
            ->assertJsonPath('data.items.0.line_total', '11.17')
            ->assertJsonPath('data.items.1.line_total', '0.03')
            ->assertJsonPath('data.total_cost', '3.35');
    }

    public function test_the_request_shape_is_validated(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop)->variants[0];
        $post = fn (array $payload) => $this->asOwnerOf($shop)->postJson('/api/v1/sales', $payload);

        $post([])->assertUnprocessable()->assertJsonValidationErrors(['client_uuid', 'items', 'grand_total', 'due_amount']);
        $post($this->salePayload([], '0'))->assertUnprocessable()->assertJsonValidationErrors('items');
        $post($this->salePayload([[$variant->id, 0]], '0'))->assertUnprocessable()->assertJsonValidationErrors('items.0.quantity');
        $post($this->salePayload([[$variant->id, -1]], '-60'))->assertUnprocessable();
        $post($this->salePayload([[$variant->id, 1]], '60', ['client_uuid' => 'not-a-uuid']))->assertUnprocessable()->assertJsonValidationErrors('client_uuid');
        $post($this->salePayload([[$variant->id, 1]], '60', ['payments' => [['method' => 'bitcoin', 'amount' => '60']]]))->assertUnprocessable()->assertJsonValidationErrors('payments.0.method');
        $post($this->salePayload([[$variant->id, 1]], '60', ['payments' => [['method' => 'cash', 'amount' => '0']]]))->assertUnprocessable()->assertJsonValidationErrors('payments.0.amount');
        $post($this->salePayload([[999999, 1]], '60'))->assertUnprocessable()->assertJsonPath('code', 'PRODUCT_UNAVAILABLE');
        $post($this->salePayload([[$variant->id, '1.5']], '90'))->assertUnprocessable()->assertJsonPath('code', 'QUANTITY_MUST_BE_WHOLE');
    }

    // --- Stock ------------------------------------------------------------------

    public function test_selling_more_than_the_stock_is_refused_and_names_the_product(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop, ['name' => 'Lux Soap'], [['purchase_price' => 1, 'selling_price' => '45', 'stock_quantity' => 3]])->variants[0];

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 4]], '180'))
            ->assertConflict()
            ->assertJsonPath('code', 'INSUFFICIENT_STOCK')
            ->assertJsonPath('errors', ['items.0.quantity' => ['Only 3 left of "Lux Soap".']]);

        $this->assertSame('3.000', $this->stockOf($variant->id));
    }

    public function test_the_same_product_on_two_lines_is_checked_against_stock_together(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop, [], [['purchase_price' => 1, 'selling_price' => '10', 'stock_quantity' => 3]])->variants[0];

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 2], [$variant->id, 2]], '40'))
            ->assertConflict()->assertJsonPath('code', 'INSUFFICIENT_STOCK');

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 2], [$variant->id, 1]], '30'))->assertCreated();
        $this->assertSame('0.000', $this->stockOf($variant->id));
    }

    public function test_the_correct_variant_is_deducted(): void
    {
        $shop = $this->createShop();
        $shirt = $this->createProduct($shop, ['name' => 'Polo'], [
            ['name' => 'S', 'purchase_price' => 200, 'selling_price' => 350, 'stock_quantity' => 4],
            ['name' => 'M', 'purchase_price' => 210, 'selling_price' => 370, 'stock_quantity' => 6],
        ]);
        [$s, $m] = $shirt->variants->all();

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$m->id, 2]], '740'))
            ->assertCreated()
            ->assertJsonPath('data.items.0.variant_name', 'M')
            ->assertJsonPath('data.items.0.unit_price', '370.00');

        $this->assertSame('4.000', $this->stockOf($s->id));
        $this->assertSame('4.000', $this->stockOf($m->id));
    }

    public function test_a_shop_that_allows_it_can_sell_below_zero(): void
    {
        $shop = $this->createShop(['settings' => ['allow_negative_stock' => true]]);
        $variant = $this->createProduct($shop, [], [['purchase_price' => 1, 'selling_price' => '10', 'stock_quantity' => 1]])->variants[0];

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 3]], '30'))->assertCreated();
        $this->assertSame('-2.000', $this->stockOf($variant->id));
    }

    // --- Profit keeps its history ------------------------------------------------

    public function test_past_profit_does_not_change_when_the_cost_or_price_changes_later(): void
    {
        $shop = $this->createShop();
        $product = $this->createProduct($shop); // cost 50, price 60
        $variant = $product->variants[0];

        $saleId = $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 2]], '120'))->json('data.id');

        // Later: new stock arrives at a higher cost, the price goes up, the product is renamed.
        $this->asOwnerOf($shop)->postJson('/api/v1/stock/in', ['variant_id' => $variant->id, 'quantity' => 10, 'unit_cost' => '58'])->assertCreated();
        $this->asOwnerOf($shop)->patchJson("/api/v1/products/{$product->id}", [
            'name' => 'Renamed', 'variants' => [['id' => $variant->id, 'purchase_price' => 58, 'selling_price' => 80]],
        ])->assertOk();

        $this->asOwnerOf($shop)->getJson("/api/v1/sales/{$saleId}")->assertOk()
            ->assertJsonPath('data.total_cost', '100.00')
            ->assertJsonPath('data.gross_profit', '20.00')
            ->assertJsonPath('data.items.0.unit_price', '60.00')
            ->assertJsonPath('data.items.0.product_name', $product->name);

        // A new sale uses the new figures.
        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '80'))
            ->assertCreated()->assertJsonPath('data.total_cost', '58.00')->assertJsonPath('data.gross_profit', '22.00');
    }

    // --- Idempotency ---------------------------------------------------------------

    public function test_sending_the_same_sale_twice_records_it_once(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop)->variants[0];
        $payload = $this->salePayload([[$variant->id, 2]], '120');

        $first = $this->asOwnerOf($shop)->postJson('/api/v1/sales', $payload)->assertCreated();
        $second = $this->asOwnerOf($shop)->postJson('/api/v1/sales', $payload)->assertOk();

        $this->assertSame($first->json('data.id'), $second->json('data.id'));
        $this->assertSame($first->json('data.invoice_no'), $second->json('data.invoice_no'));
        $this->assertSame('8.000', $this->stockOf($variant->id), 'Stock is deducted once.');

        $this->tenant()->runFor($shop, function () {
            $this->assertSame(1, Sale::query()->count());
            $this->assertSame(1, Payment::query()->count());
        });

        // A retry is answered with the stored sale even if the stock has since run out.
        $this->asOwnerOf($shop)->postJson('/api/v1/stock/adjust', ['variant_id' => $variant->id, 'new_quantity' => 0])->assertCreated();
        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $payload)->assertOk()->assertJsonPath('data.id', $first->json('data.id'));
    }

    public function test_the_same_client_id_in_two_shops_is_two_sales(): void
    {
        $a = $this->createShop();
        $b = $this->createShop();
        $uuid = (string) Str::uuid();

        $this->asOwnerOf($a)->postJson('/api/v1/sales', $this->salePayload([[$this->createProduct($a)->variants[0]->id, 1]], '60', ['client_uuid' => $uuid]))->assertCreated();
        $this->asOwnerOf($b)->postJson('/api/v1/sales', $this->salePayload([[$this->createProduct($b)->variants[0]->id, 1]], '60', ['client_uuid' => $uuid]))->assertCreated();
    }

    // --- Listing, permissions, limits -----------------------------------------------

    public function test_sales_can_be_listed_and_filtered(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop, [], [['purchase_price' => 1, 'selling_price' => '100', 'stock_quantity' => 50]])->variants[0];

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '100'))->assertCreated();
        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 2]], '200', ['payments' => [['method' => 'bkash', 'amount' => '200', 'transaction_id' => '9XK2L0']]]))->assertCreated();
        $this->travel(-3)->days();
        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 3]], '300'))->assertCreated();
        $this->travelBack();

        $count = fn (string $query) => count($this->asOwnerOf($shop)->getJson('/api/v1/sales?'.$query)->assertOk()->json('data'));

        $this->assertSame(3, $count(''));
        $this->assertSame(1, $count('payment_method=bkash'));
        $this->assertSame(2, $count('from='.now('Asia/Dhaka')->toDateString()));
        $this->assertSame(1, $count('to='.now('Asia/Dhaka')->subDay()->toDateString()));
        $this->assertSame(1, $count('q=000002'));
        $this->assertSame(0, $count('status=voided'));

        // Newest first.
        $this->assertSame(['INV-000002', 'INV-000001', 'INV-000003'], $this->asOwnerOf($shop)->getJson('/api/v1/sales')->json('data.*.invoice_no'));
    }

    public function test_a_cashier_can_sell_but_does_not_see_cost_or_profit(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop)->variants[0];
        $cashier = $this->addMember($shop, ShopRole::Cashier);

        $response = $this->asUser($cashier)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '60'))->assertCreated();

        $response->assertJsonMissingPath('data.total_cost')->assertJsonMissingPath('data.gross_profit');
        $this->asUser($cashier)->getJson('/api/v1/sales')->assertOk()->assertJsonMissingPath('data.0.gross_profit');
    }

    public function test_the_plans_monthly_sales_limit_is_enforced(): void
    {
        $shop = $this->createShop();
        Plan::query()->where('code', 'free')->update(['max_monthly_sales' => 2]);
        $variant = $this->createProduct($shop)->variants[0];
        $sell = fn () => $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '60'));

        $sell()->assertCreated();
        $sell()->assertCreated();
        $sell()->assertForbidden()->assertJsonPath('code', 'PLAN_LIMIT_REACHED');

        // A new month starts a new count.
        $this->travelTo(now()->addMonthNoOverflow()->startOfMonth()->addDay());
        $sell()->assertCreated();
    }

    public function test_the_database_refuses_a_sale_whose_figures_do_not_add_up(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop)->variants[0];
        $id = $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '60'))->json('data.id');

        // Even a bug that bypassed every service could not store inconsistent totals.
        $this->expectException(QueryException::class);
        DB::table('sales')->where('id', $id)->update(['paid_amount' => '10.00']);
    }
}
