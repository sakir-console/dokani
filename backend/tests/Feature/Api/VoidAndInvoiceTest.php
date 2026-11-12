<?php

namespace Tests\Feature\Api;

use App\Enums\ShopRole;
use App\Models\Customer;
use App\Models\Invoice;
use App\Models\Payment;
use App\Models\ProductVariant;
use App\Models\StockMovement;
use Illuminate\Support\Str;
use Tests\TestCase;

class VoidAndInvoiceTest extends TestCase
{
    /** A sale of 2 × 500 with 600 cash and 400 due to a customer. */
    private function dueSale(): array
    {
        $shop = $this->createShop(['name' => 'Rahim Store', 'address' => 'Mirpur 10, Dhaka', 'phone' => '01711000001']);
        $variant = $this->createProduct($shop, ['name' => 'লাক্স সাবান'], [['purchase_price' => '350', 'selling_price' => '500', 'stock_quantity' => 10]])->variants[0];

        $sale = $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 2]], '1000', [
            'payments' => [['method' => 'cash', 'amount' => '400'], ['method' => 'bkash', 'amount' => '200', 'transaction_id' => 'TX9']],
            'due_amount' => '400',
            'customer' => ['name' => 'Karim Mia', 'phone' => '01812345678'],
        ]))->assertCreated()->json('data');

        return [$shop, $variant, $sale];
    }

    private function token(array $sale): string
    {
        return Str::afterLast($sale['invoice_url'], '/');
    }

    // --- Voiding ------------------------------------------------------------------

    public function test_voiding_a_sale_reverses_stock_due_and_payments_without_deleting_anything(): void
    {
        [$shop, $variant, $sale] = $this->dueSale();

        $this->asOwnerOf($shop)->postJson("/api/v1/sales/{$sale['id']}/void", [])->assertUnprocessable()->assertJsonValidationErrors('reason');

        $this->asOwnerOf($shop)->postJson("/api/v1/sales/{$sale['id']}/void", ['reason' => 'Customer returned everything'])
            ->assertOk()
            ->assertJsonPath('data.status', 'voided')
            ->assertJsonPath('data.void_reason', 'Customer returned everything')
            ->assertJsonPath('data.customer.current_due', '0.00');

        $this->tenant()->runFor($shop, function () use ($variant, $sale) {
            // Stock is back, through a movement of its own.
            $this->assertSame('10.000', ProductVariant::query()->findOrFail($variant->id)->stock_quantity);
            $this->assertSame(['opening', 'sale', 'sale_void'], StockMovement::query()->orderBy('id')->pluck('type')->map->value->all());

            // The due is taken off by a new ledger entry; the original stays.
            $customer = Customer::query()->sole();
            $this->assertSame('0.00', $customer->current_due);
            $this->assertSame('0.00', $customer->total_purchases);
            $this->assertSame('0.00', $customer->total_paid);
            $this->assertSame(['sale_due', 'sale_void'], $customer->ledger()->orderBy('id')->pluck('type')->map->value->all());

            // Money taken is recorded as refunded, method by method.
            $refunds = Payment::query()->where('type', 'refund')->orderBy('id')->get();
            $this->assertSame(['cash', 'bkash'], $refunds->pluck('method')->map->value->all());
            $this->assertSame(['400.00', '200.00'], $refunds->pluck('amount')->all());
            $this->assertSame(4, Payment::query()->where('sale_id', $sale['id'])->count());
        });

        $this->assertDatabaseHas('audit_logs', ['shop_id' => $shop->id, 'action' => 'sale.voided']);

        // Cannot be done twice.
        $this->asOwnerOf($shop)->postJson("/api/v1/sales/{$sale['id']}/void", ['reason' => 'again'])
            ->assertConflict()->assertJsonPath('code', 'SALE_ALREADY_VOIDED');
    }

    public function test_voiding_after_the_due_was_paid_leaves_the_customer_in_credit(): void
    {
        [$shop, , $sale] = $this->dueSale();
        $customerId = $sale['customer']['id'];

        $this->asOwnerOf($shop)->postJson("/api/v1/customers/{$customerId}/collect-due", [
            'client_uuid' => (string) Str::uuid(), 'amount' => '400', 'method' => 'cash',
        ])->assertCreated();

        $this->asOwnerOf($shop)->postJson("/api/v1/sales/{$sale['id']}/void", ['reason' => 'Returned'])->assertOk();

        // They paid 400 against a due that no longer exists: the shop owes them 400.
        $this->asOwnerOf($shop)->getJson("/api/v1/customers/{$customerId}")->assertJsonPath('data.current_due', '-400.00');
    }

    public function test_a_sale_can_be_voided_after_its_product_was_deleted(): void
    {
        [$shop, $variant, $sale] = $this->dueSale();

        $this->asOwnerOf($shop)->deleteJson("/api/v1/products/{$variant->product_id}")->assertNoContent();
        $this->asOwnerOf($shop)->postJson("/api/v1/sales/{$sale['id']}/void", ['reason' => 'Mistake'])->assertOk();

        $stock = $this->tenant()->withoutTenancy(fn () => ProductVariant::query()->withTrashed()->whereKey($variant->id)->value('stock_quantity'));
        $this->assertSame('10.000', $stock);
    }

    public function test_only_roles_with_permission_can_void(): void
    {
        [$shop, , $sale] = $this->dueSale();
        $cashier = $this->addMember($shop, ShopRole::Cashier);
        $manager = $this->addMember($shop, ShopRole::Manager);

        $this->asUser($cashier)->postJson("/api/v1/sales/{$sale['id']}/void", ['reason' => 'x'])->assertForbidden();
        $this->asUser($manager)->postJson("/api/v1/sales/{$sale['id']}/void", ['reason' => 'x'])->assertOk();
    }

    // --- Public invoice --------------------------------------------------------------

    public function test_the_public_invoice_page_shows_the_bill_without_a_login(): void
    {
        [, , $sale] = $this->dueSale();
        $this->resetRequestState();

        $response = $this->get('/i/'.$this->token($sale));

        $response->assertOk()
            ->assertSee('Rahim Store')
            ->assertSee('Mirpur 10, Dhaka')
            ->assertSee('INV-000001')
            ->assertSee('লাক্স সাবান')
            ->assertSee('2 × ৳500')
            ->assertSee('৳1,000')
            ->assertSee('Paid · Cash')
            ->assertSee('Paid · bKash')
            ->assertSee('Due')
            ->assertSee('৳400')
            ->assertSee('Karim Mia')
            ->assertHeader('X-Robots-Tag', 'noindex, nofollow');

        // Private details stay private.
        $response->assertSee('018*****678')
            ->assertDontSee('01812345678')
            ->assertDontSee('TX9')
            ->assertDontSee('350'); // purchase cost
    }

    public function test_the_public_json_exposes_no_ids_cost_or_full_phone(): void
    {
        [, , $sale] = $this->dueSale();
        $this->resetRequestState();

        $response = $this->getJson('/api/v1/public/invoices/'.$this->token($sale))->assertOk();

        $response->assertJsonPath('data.invoice_no', 'INV-000001')
            ->assertJsonPath('data.grand_total', '1000.00')
            ->assertJsonPath('data.due_amount', '400.00')
            ->assertJsonPath('data.customer.phone_masked', '018*****678')
            ->assertJsonPath('data.payments.1.label', 'bKash');

        $body = $response->getContent();
        foreach (['"id"', 'shop_id', 'customer_id', 'unit_cost', 'total_cost', 'transaction_id', '01812345678', 'public_token'] as $leak) {
            $this->assertStringNotContainsString($leak, $body, "The public invoice must not contain {$leak}.");
        }
    }

    public function test_a_wrong_or_malformed_token_shows_nothing(): void
    {
        [, , $sale] = $this->dueSale();
        $this->resetRequestState();
        $token = $this->token($sale);

        $this->get('/i/'.str_repeat('A', 43))->assertNotFound();
        $this->get('/i/'.substr($token, 0, 42))->assertNotFound();
        $this->get('/i/'.$token.'x')->assertNotFound();
        $this->get('/i/'.$sale['id'])->assertNotFound();          // the database id is not a credential
        $this->get('/i/INV-000001')->assertNotFound();            // nor is the invoice number
        $this->getJson('/api/v1/public/invoices/1')->assertNotFound();
    }

    public function test_tokens_are_long_random_and_different_for_every_sale(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop, [], [['purchase_price' => 1, 'selling_price' => 1, 'stock_quantity' => 100]])->variants[0];

        $tokens = [];
        foreach (range(1, 20) as $ignored) {
            $tokens[] = Str::afterLast($this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '1'))->json('data.invoice_url'), '/');
        }

        $this->assertCount(20, array_unique($tokens));
        foreach ($tokens as $token) {
            $this->assertMatchesRegularExpression('/^[A-Za-z0-9_-]{43}$/', $token); // 32 random bytes
        }
        // The token is never included in JSON by accident.
        $this->tenant()->runFor($shop, fn () => $this->assertArrayNotHasKey('public_token', Invoice::query()->first()->toArray()));
    }

    public function test_the_invoice_keeps_the_shop_details_from_the_day_of_the_sale(): void
    {
        [$shop, , $sale] = $this->dueSale();

        $this->asOwnerOf($shop)->patchJson('/api/v1/shop', ['name' => 'New Name Ltd', 'address' => 'Moved away'])->assertOk();
        $this->resetRequestState();

        $this->get('/i/'.$this->token($sale))->assertOk()->assertSee('Rahim Store')->assertSee('Mirpur 10, Dhaka')->assertDontSee('New Name Ltd');
    }

    public function test_a_voided_sale_says_so_on_its_invoice(): void
    {
        [$shop, , $sale] = $this->dueSale();
        $this->asOwnerOf($shop)->postJson("/api/v1/sales/{$sale['id']}/void", ['reason' => 'x'])->assertOk();
        $this->resetRequestState();

        $this->get('/i/'.$this->token($sale))->assertOk()->assertSee('This sale was cancelled.');
    }

    public function test_public_invoice_requests_are_rate_limited(): void
    {
        [, , $sale] = $this->dueSale();
        $this->resetRequestState();

        for ($i = 0; $i < 30; $i++) {
            $this->get('/i/'.str_repeat('B', 43))->assertNotFound();
        }
        $this->get('/i/'.$this->token($sale))->assertTooManyRequests();
    }

    // --- PDF ----------------------------------------------------------------------

    public function test_the_invoice_pdf_is_a_real_pdf_containing_the_bill_in_bangla(): void
    {
        [$shop, , $sale] = $this->dueSale();

        $pdf = $this->asOwnerOf($shop)->get("/api/v1/sales/{$sale['id']}/invoice.pdf");
        $pdf->assertOk()->assertHeader('Content-Type', 'application/pdf');
        $this->assertStringStartsWith('%PDF-', $pdf->getContent());

        $text = $this->pdfText($pdf->getContent());
        $this->assertStringContainsString('Rahim Store', $text);
        $this->assertStringContainsString('INV-000001', $text);
        $this->assertStringContainsString('1,000', $text);
        $this->assertStringContainsString('Karim Mia', $text);
        $this->assertStringNotContainsString('01812345678', $text);

        // Receipt widths produce narrow pages; the public link gives the same document.
        foreach (['80' => 226.8, '58' => 164.4] as $width => $points) {
            $receipt = $this->asOwnerOf($shop)->get("/api/v1/sales/{$sale['id']}/invoice.pdf?width={$width}")->assertOk()->getContent();
            $this->assertSame(1, preg_match('/MediaBox\s*\[\s*0\s+0\s+([\d.]+)/', $receipt, $match));
            $this->assertEqualsWithDelta($points, (float) $match[1], 1.0, "A {$width}mm receipt is {$width}mm wide.");
        }

        $this->resetRequestState();
        $public = $this->get('/i/'.$this->token($sale).'/pdf')->assertOk();
        $this->assertStringStartsWith('%PDF-', $public->getContent());
        $this->get('/i/'.str_repeat('C', 43).'/pdf')->assertNotFound();
    }

    private function pdfText(string $pdf): string
    {
        $path = tempnam(sys_get_temp_dir(), 'inv').'.pdf';
        file_put_contents($path, $pdf);
        $text = (string) shell_exec('pdftotext -layout '.escapeshellarg($path).' - 2>/dev/null');
        @unlink($path);

        if ($text === '') {
            $this->markTestSkipped('pdftotext is not installed; cannot read the PDF text.');
        }

        return $text;
    }

    // --- Dashboard ------------------------------------------------------------------

    public function test_the_dashboard_reports_todays_sales_and_profit_separately(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop, [], [['purchase_price' => '70', 'selling_price' => '100', 'stock_quantity' => 100]])->variants[0];
        $customer = ['customer' => ['name' => 'K', 'phone' => '01812345678']];

        // Yesterday's sale must not count.
        $this->travel(-1)->days();
        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 5]], '500'))->assertCreated();
        $this->travelBack();

        // Today: 2 × 100 − 10 discount + 20 charge = 210, all paid.
        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 2]], '210', ['discount_amount' => '10', 'additional_charge' => '20']))->assertCreated();
        // Today: 3 × 100 = 300, 100 paid, 200 due.
        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 3]], '300', ['payments' => [['method' => 'cash', 'amount' => '100']], 'due_amount' => '200'] + $customer))->assertCreated();
        // Today, then cancelled: must not count.
        $voided = $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '100'))->json('data.id');
        $this->asOwnerOf($shop)->postJson("/api/v1/sales/{$voided}/void", ['reason' => 'x'])->assertOk();

        $this->asOwnerOf($shop)->getJson('/api/v1/dashboard')->assertOk()
            ->assertJsonPath('data.today.sales', '510.00')
            ->assertJsonPath('data.today.orders', 2)
            ->assertJsonPath('data.today.items_sold', '5.000')
            ->assertJsonPath('data.today.paid', '310.00')
            ->assertJsonPath('data.today.due', '200.00')
            // Revenue 190 + 300 = 490; cost 5 × 70 = 350; +20 charge counted as income → 160. Not the same as sales.
            ->assertJsonPath('data.today.profit', '160.00')
            ->assertJsonPath('data.total_customer_due', '200.00')
            ->assertJsonPath('data.customers_with_due', 1)
            ->assertJsonPath('data.stock.total_products', 1)
            ->assertJsonCount(4, 'data.recent_sales');

        // A shop that does not treat charges as income sees profit on goods only.
        $this->asOwnerOf($shop)->patchJson('/api/v1/shop/settings', ['charge_counts_as_income' => false])->assertOk();
        $this->asOwnerOf($shop)->getJson('/api/v1/dashboard')->assertJsonPath('data.today.profit', '140.00');

        // A cashier sees sales but not profit.
        $cashier = $this->addMember($shop, ShopRole::Cashier);
        $this->asUser($cashier)->getJson('/api/v1/dashboard')->assertOk()
            ->assertJsonPath('data.today.sales', '510.00')->assertJsonMissingPath('data.today.profit');
    }

    public function test_today_follows_the_shops_time_zone_not_utc(): void
    {
        $shop = $this->createShop(); // Asia/Dhaka, UTC+6
        $variant = $this->createProduct($shop, [], [['purchase_price' => 1, 'selling_price' => '100', 'stock_quantity' => 100]])->variants[0];

        // 23:30 in Dhaka on the 10th (17:30 UTC).
        $this->travelTo('2026-03-10 17:30:00');
        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '100'))->assertCreated();

        // 00:30 in Dhaka on the 11th (18:30 UTC, still the 10th in UTC): a new business day.
        $this->travelTo('2026-03-10 18:30:00');
        $this->asOwnerOf($shop)->getJson('/api/v1/dashboard')->assertJsonPath('data.today.sales', '0.00')->assertJsonPath('data.today.orders', 0);

        $this->asOwnerOf($shop)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 2]], '200'))->assertCreated();
        $this->asOwnerOf($shop)->getJson('/api/v1/dashboard')->assertJsonPath('data.today.sales', '200.00');
    }
}
