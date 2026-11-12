<?php

namespace Tests\Feature\Api;

use App\Enums\ShopRole;
use App\Models\Shop;
use Illuminate\Support\Str;
use PhpOffice\PhpSpreadsheet\IOFactory;
use Tests\TestCase;

class ReportTest extends TestCase
{
    private Shop $shop;

    private int $soap;   // cost 30, price 50, pieces

    private int $rice;   // cost 60, price 80, kilograms

    protected function setUp(): void
    {
        parent::setUp();

        $this->shop = $this->createShop(['name' => 'রহিম স্টোর']);
        $this->subscribe($this->shop, 'standard'); // reports + exports

        $this->soap = $this->createProduct($this->shop, ['name' => 'Lux Soap'], [['purchase_price' => '30', 'selling_price' => '50', 'stock_quantity' => 100]])->variants[0]->id;
        $this->rice = $this->createProduct($this->shop, ['name' => 'মিনিকেট চাল', 'unit_id' => $this->unitId('Kilogram')], [['purchase_price' => '60', 'selling_price' => '80', 'stock_quantity' => 100]])->variants[0]->id;
    }

    private function sell(array $lines, string $total, array $overrides = []): array
    {
        return $this->asOwnerOf($this->shop)->postJson('/api/v1/sales', $this->salePayload($lines, $total, $overrides))->assertCreated()->json('data');
    }

    private function report(string $path, string $query = ''): array
    {
        return $this->asOwnerOf($this->shop)->getJson("/api/v1/reports/{$path}".($query ? "?{$query}" : ''))->assertOk()->json();
    }

    /**
     * Today's trading:
     *   A  2 soap + 1 kg rice, 10 off the bill, 5 delivery charge → 175, paid cash
     *   B  4 soap with 20 off the line → 180: 100 bKash, 80 due (Karim)
     *   C  1 soap → 50 cash, then cancelled
     *   and Karim pays 30 of his due by Nagad
     */
    private function tradeToday(): array
    {
        $a = $this->sell([[$this->soap, 2], [$this->rice, 1]], '175', ['discount_amount' => '10', 'additional_charge' => '5']);
        $b = $this->sell([[$this->soap, 4, ['discount_amount' => '20']]], '180', [
            'payments' => [['method' => 'bkash', 'amount' => '100', 'transaction_id' => 'TX1']],
            'due_amount' => '80',
            'customer' => ['name' => 'Karim Mia', 'phone' => '01812345678'],
        ]);
        $c = $this->sell([[$this->soap, 1]], '50');
        $this->asOwnerOf($this->shop)->postJson("/api/v1/sales/{$c['id']}/void", ['reason' => 'Mistake'])->assertOk();

        $this->asOwnerOf($this->shop)->postJson("/api/v1/customers/{$b['customer']['id']}/collect-due", [
            'client_uuid' => (string) Str::uuid(), 'amount' => '30', 'method' => 'nagad',
        ])->assertCreated();

        return [$a, $b, $c];
    }

    // --- Summary ------------------------------------------------------------------

    public function test_the_summary_separates_sales_revenue_and_profit(): void
    {
        $this->tradeToday();

        $summary = $this->report('summary')['data'];

        $this->assertSame([
            'orders' => 2,
            'items_sold' => '7.000',            // 2 + 1 + 4; the cancelled sale is not counted
            'total_sales' => '355.00',          // 175 + 180
            'total_paid' => '275.00',           // 175 + 100
            'total_due' => '80.00',
            'total_discounts' => '30.00',       // 10 on the bill + 20 on a line
            'additional_charges' => '5.00',
            'revenue' => '350.00',              // goods after discounts: (180 − 10) + 180
            'cost_of_goods' => '240.00',        // (2×30 + 1×60) + 4×30
            'gross_profit' => '115.00',         // 350 − 240 + 5 charge counted as income
            'charges_counted_as_income' => true,
            'due_collected' => '30.00',
            'cancelled_orders' => 1,
            'cancelled_amount' => '50.00',
        ], $summary);

        // Total = Paid + Due holds for the period as it does for each sale.
        $this->assertSame((float) $summary['total_sales'], (float) $summary['total_paid'] + (float) $summary['total_due']);
        // Sales and profit are different numbers.
        $this->assertNotSame($summary['total_sales'], $summary['gross_profit']);

        // A shop that does not treat charges as income sees profit on goods only.
        $this->asOwnerOf($this->shop)->patchJson('/api/v1/shop/settings', ['charge_counts_as_income' => false])->assertOk();
        $this->assertSame('110.00', $this->report('summary')['data']['gross_profit']);
    }

    public function test_an_empty_period_reports_zeros_not_errors(): void
    {
        $summary = $this->report('summary', 'range=yesterday')['data'];

        $this->assertSame(0, $summary['orders']);
        $this->assertSame('0.00', $summary['total_sales']);
        $this->assertSame('0.00', $summary['gross_profit']);
        $this->assertSame('0.000', $summary['items_sold']);
    }

    public function test_profit_in_a_report_uses_the_cost_at_the_time_of_each_sale(): void
    {
        $this->sell([[$this->soap, 1]], '50'); // cost 30 → profit 20

        // The cost rises afterwards.
        $this->asOwnerOf($this->shop)->postJson('/api/v1/stock/in', ['variant_id' => $this->soap, 'quantity' => 10, 'unit_cost' => '45'])->assertCreated();
        $this->sell([[$this->soap, 1]], '50'); // cost 45 → profit 5

        $summary = $this->report('summary')['data'];
        $this->assertSame('75.00', $summary['cost_of_goods']);
        $this->assertSame('25.00', $summary['gross_profit'], 'Not 10 (both at the new cost) and not 40 (both at the old cost).');
    }

    // --- Date ranges ----------------------------------------------------------------

    public function test_date_ranges_follow_the_shops_calendar(): void
    {
        // Thursday 12 March 2026, 10:00 in Dhaka.
        $this->travelTo('2026-03-12 04:00:00');

        $at = function (string $utc, string $total) {
            $this->travelTo($utc);
            $this->sell([[$this->soap, (int) ($total / 50)]], $total);
        };

        $at('2026-02-28 17:30:00', '50');   // 28 Feb 23:30 Dhaka — last month
        $at('2026-02-28 18:30:00', '100');  //  1 Mar 00:30 Dhaka — this month
        $at('2026-03-05 06:00:00', '150');  //  5 Mar (Thu) — 8 days ago
        $at('2026-03-06 18:30:00', '200');  //  7 Mar 00:30 (Sat) — this week starts Saturday
        $at('2026-03-10 17:59:00', '250');  // 10 Mar 23:59 Dhaka
        $at('2026-03-10 18:01:00', '300');  // 11 Mar 00:01 Dhaka — yesterday
        $at('2026-03-11 18:01:00', '350');  // 12 Mar 00:01 Dhaka — today
        $this->travelTo('2026-03-12 04:00:00');

        $total = fn (string $query) => $this->report('summary', $query)['data']['total_sales'];

        $this->assertSame('350.00', $total('range=today'));
        $this->assertSame('350.00', $total(''), 'Today is the default.');
        $this->assertSame('300.00', $total('range=yesterday'));
        $this->assertSame('1100.00', $total('range=last_7_days'));   // 6–12 Mar: 200 + 250 + 300 + 350
        $this->assertSame('1100.00', $total('range=this_week'));     // from Saturday 7 Mar
        $this->assertSame('1350.00', $total('range=this_month'));    // everything except 28 Feb
        $this->assertSame('550.00', $total('range=custom&from=2026-03-10&to=2026-03-11'));
        $this->assertSame('50.00', $total('range=custom&from=2026-02-28&to=2026-02-28'));

        $meta = $this->report('summary', 'range=this_week')['meta']['range'];
        $this->assertSame(['key' => 'this_week', 'from' => '2026-03-07', 'to' => '2026-03-12', 'label' => '7 Mar 2026 – 12 Mar 2026'], $meta);
    }

    public function test_custom_ranges_are_validated(): void
    {
        $get = fn (string $query) => $this->asOwnerOf($this->shop)->getJson('/api/v1/reports/summary?'.$query);

        $get('range=custom')->assertUnprocessable()->assertJsonValidationErrors('from');
        $get('range=custom&from=2026-03-10&to=2026-03-01')->assertUnprocessable()->assertJsonValidationErrors('to');
        $get('range=custom&from=2024-01-01&to=2026-03-01')->assertUnprocessable()->assertJsonValidationErrors('to');
        $get('range=custom&from=10/03/2026&to=2026-03-11')->assertUnprocessable()->assertJsonValidationErrors('from');
        $get('range=forever')->assertUnprocessable()->assertJsonValidationErrors('range');
    }

    public function test_the_daily_breakdown_has_a_row_for_every_day_including_empty_ones(): void
    {
        $this->travelTo('2026-03-12 04:00:00');
        $this->sell([[$this->soap, 2]], '100');
        $this->travelTo('2026-03-10 04:00:00');
        $this->sell([[$this->soap, 1]], '50');
        $this->travelTo('2026-03-12 05:00:00');

        $days = $this->report('daily', 'range=custom&from=2026-03-09&to=2026-03-12')['data'];

        $this->assertSame(['2026-03-09', '2026-03-10', '2026-03-11', '2026-03-12'], array_column($days, 'date'));
        $this->assertSame(['0.00', '50.00', '0.00', '100.00'], array_column($days, 'sales'));
        $this->assertSame([0, 1, 0, 1], array_column($days, 'orders'));
        $this->assertSame(['0.00', '20.00', '0.00', '40.00'], array_column($days, 'profit'));
    }

    // --- Payment methods ----------------------------------------------------------------

    public function test_payment_methods_show_money_in_and_out_by_method(): void
    {
        $this->tradeToday();

        $report = $this->report('payment-methods')['data'];
        $byMethod = collect($report['methods'])->keyBy('method');

        // Cash: sale A 175 and sale C 50 came in; C's 50 went back out when it was cancelled.
        $this->assertSame(['sales' => '225.00', 'due_collections' => '0.00', 'refunds' => '50.00', 'net' => '175.00'],
            collect($byMethod['cash'])->only(['sales', 'due_collections', 'refunds', 'net'])->all());
        $this->assertSame('100.00', $byMethod['bkash']['net']);
        $this->assertSame(['sales' => '0.00', 'due_collections' => '30.00', 'refunds' => '0.00', 'net' => '30.00'],
            collect($byMethod['nagad'])->only(['sales', 'due_collections', 'refunds', 'net'])->all());
        $this->assertArrayNotHasKey('card', $byMethod->all(), 'Unused methods are left out.');

        $this->assertSame(['sales' => '325.00', 'due_collections' => '30.00', 'refunds' => '50.00', 'net' => '305.00'], $report['totals']);
        // Due is not a payment method: it is reported as what was sold on credit.
        $this->assertSame('80.00', $report['sold_on_due']);
    }

    // --- Best sellers --------------------------------------------------------------------

    public function test_best_sellers_can_be_ranked_by_quantity_or_revenue(): void
    {
        $this->sell([[$this->soap, 10]], '500');
        $this->sell([[$this->rice, '7.5']], '600');
        $voided = $this->sell([[$this->rice, 50]], '4000');
        $this->asOwnerOf($this->shop)->postJson("/api/v1/sales/{$voided['id']}/void", ['reason' => 'x'])->assertOk();

        $byQuantity = $this->report('best-sellers')['data'];
        $this->assertSame(['Lux Soap', 'মিনিকেট চাল'], array_column($byQuantity, 'product_name'));
        $this->assertSame(['quantity' => '10.000', 'revenue' => '500.00', 'profit' => '200.00'],
            collect($byQuantity[0])->only(['quantity', 'revenue', 'profit'])->all());

        $byRevenue = $this->report('best-sellers', 'by=revenue')['data'];
        $this->assertSame(['মিনিকেট চাল', 'Lux Soap'], array_column($byRevenue, 'product_name'));
        $this->assertSame(['quantity' => '7.500', 'revenue' => '600.00', 'profit' => '150.00'],
            collect($byRevenue[0])->only(['quantity', 'revenue', 'profit'])->all());

        $this->assertCount(1, $this->report('best-sellers', 'limit=1')['data']);
    }

    public function test_a_product_deleted_since_still_appears_in_best_sellers_under_its_name_at_the_time(): void
    {
        $product = $this->createProduct($this->shop, ['name' => 'Seasonal Item']);
        $this->sell([[$product->variants[0]->id, 3]], '180');
        $this->asOwnerOf($this->shop)->deleteJson("/api/v1/products/{$product->id}")->assertNoContent();

        $this->assertSame(['Seasonal Item'], array_column($this->report('best-sellers')['data'], 'product_name'));
    }

    // --- Stock and dues ---------------------------------------------------------------------

    public function test_the_low_stock_report_lists_low_and_empty_variants_emptiest_first(): void
    {
        $this->createProduct($this->shop, ['name' => 'Nearly gone'], [['purchase_price' => 1, 'selling_price' => 2, 'stock_quantity' => 2]]);
        $this->createProduct($this->shop, ['name' => 'Gone'], [['purchase_price' => 1, 'selling_price' => 2, 'stock_quantity' => 0]]);
        $this->createProduct($this->shop, ['name' => 'Own rule', 'low_stock_threshold' => '50'], [['purchase_price' => 1, 'selling_price' => 2, 'stock_quantity' => 40]]);

        $report = $this->report('low-stock');

        $this->assertSame(['Gone', 'Nearly gone', 'Own rule'], array_column($report['data'], 'product_name'));
        $this->assertSame(['out', 'low', 'low'], array_column($report['data'], 'status'));
        $this->assertSame(['5.000', '5.000', '50.000'], array_column($report['data'], 'threshold'));
        $this->assertSame(3, $report['meta']['total']);
    }

    public function test_the_dues_report_lists_who_owes_what_largest_first(): void
    {
        $sellOnDue = fn (string $name, string $phone, int $pieces) => $this->sell([[$this->soap, $pieces]], (string) ($pieces * 50), [
            'payments' => [], 'due_amount' => (string) ($pieces * 50), 'customer' => ['name' => $name, 'phone' => $phone],
        ]);
        $sellOnDue('Small', '01711111111', 1);
        $sellOnDue('Large', '01722222222', 6);
        $this->sell([[$this->soap, 1]], '50', ['customer' => ['name' => 'Paid Up', 'phone' => '01733333333']]);

        $report = $this->report('dues');

        $this->assertSame(['Large', 'Small'], array_column($report['data'], 'name'));
        $this->assertSame(['300.00', '50.00'], array_column($report['data'], 'current_due'));
        $this->assertSame(2, $report['meta']['customers']);
        $this->assertSame('350.00', $report['meta']['total_due']);
    }

    public function test_the_sales_report_lists_the_periods_sales_with_cancelled_ones_marked(): void
    {
        [$a, $b, $c] = $this->tradeToday();

        $report = $this->report('sales');

        $this->assertSame([$c['invoice_no'], $b['invoice_no'], $a['invoice_no']], array_column($report['data'], 'invoice_no'));
        $this->assertSame(['voided', 'completed', 'completed'], array_column($report['data'], 'status'));
        $this->assertSame(3, $report['meta']['total']);
        $this->assertSame(0, $this->report('sales', 'range=yesterday')['meta']['total']);
    }

    // --- Access -----------------------------------------------------------------------------

    public function test_reports_need_the_plan_and_the_permission(): void
    {
        $free = $this->createShop();
        $this->asOwnerOf($free)->getJson('/api/v1/reports/summary')->assertForbidden()->assertJsonPath('code', 'MODULE_NOT_AVAILABLE');

        // Reports reveal cost and profit: a cashier may not open them.
        $cashier = $this->addMember($this->shop, ShopRole::Cashier);
        foreach (['summary', 'daily', 'payment-methods', 'best-sellers', 'low-stock', 'sales', 'dues'] as $report) {
            $this->asUser($cashier)->getJson("/api/v1/reports/{$report}")->assertForbidden()->assertJsonPath('code', 'FORBIDDEN');
        }
        $this->asUser($cashier)->get('/api/v1/reports/summary/export?format=csv', ['Accept' => 'application/json'])->assertForbidden();

        $manager = $this->addMember($this->shop, ShopRole::Manager);
        $this->asUser($manager)->getJson('/api/v1/reports/summary')->assertOk();
    }

    public function test_reports_contain_only_the_current_shops_figures(): void
    {
        $this->tradeToday();

        $other = $this->createShop();
        $this->subscribe($other, 'standard');
        $variant = $this->createProduct($other, ['name' => 'Other Shop Item'], [['purchase_price' => 1, 'selling_price' => 9999, 'stock_quantity' => 2]])->variants[0];
        $this->asOwnerOf($other)->postJson('/api/v1/sales', $this->salePayload([[$variant->id, 1]], '9999', [
            'payments' => [], 'due_amount' => '9999', 'customer' => ['name' => 'Their Customer', 'phone' => '01911111111'],
        ]))->assertCreated();

        $this->assertSame('355.00', $this->report('summary')['data']['total_sales']);
        $this->assertNotContains('Other Shop Item', array_column($this->report('best-sellers')['data'], 'product_name'));
        $this->assertNotContains('Other Shop Item', array_column($this->report('low-stock')['data'], 'product_name'));
        $this->assertSame(['Karim Mia'], array_column($this->report('dues')['data'], 'name'));
        $this->assertSame('50.00', $this->report('dues')['meta']['total_due']);
        $this->assertSame('80.00', $this->report('payment-methods')['data']['sold_on_due']);
        $this->assertCount(3, $this->report('sales')['data']);

        $csv = $this->asOwnerOf($this->shop)->get('/api/v1/reports/dues/export?format=csv')->assertOk()->getContent();
        $this->assertStringNotContainsString('Their Customer', $csv);

        $theirs = $this->asOwnerOf($other)->getJson('/api/v1/reports/summary')->json('data');
        $this->assertSame('9999.00', $theirs['total_sales']);
        $this->assertSame(1, $theirs['orders']);
    }

    // --- Exports ----------------------------------------------------------------------------

    public function test_exports_need_a_plan_that_includes_them(): void
    {
        $basic = $this->createShop();
        $this->subscribe($basic, 'basic'); // reports yes, exports no

        $this->asOwnerOf($basic)->getJson('/api/v1/reports/summary')->assertOk();
        $this->asOwnerOf($basic)->get('/api/v1/reports/summary/export?format=csv', ['Accept' => 'application/json'])
            ->assertForbidden()->assertJsonPath('code', 'MODULE_NOT_AVAILABLE');
    }

    public function test_the_csv_export_opens_correctly_in_excel_with_bangla_and_phone_numbers_intact(): void
    {
        $this->tradeToday();

        $response = $this->asOwnerOf($this->shop)->get('/api/v1/reports/sales/export?format=csv')->assertOk();
        $this->assertStringContainsString('text/csv', $response->headers->get('Content-Type'));
        $this->assertStringContainsString('attachment; filename="sales-', $response->headers->get('Content-Disposition'));

        $csv = $response->getContent();
        $this->assertStringStartsWith("\xEF\xBB\xBF", $csv, 'A UTF-8 byte-order mark lets Excel read Bangla.');

        $rows = array_map('str_getcsv', preg_split('/\r\n|\n/', trim(substr($csv, 3))));
        $this->assertSame(['Invoice', 'Date', 'Customer', 'Phone', 'Items', 'Subtotal', 'Discount', 'Charge', 'Total', 'Paid', 'Due', 'Status'], $rows[0]);
        $this->assertCount(4, $rows);

        $due = collect($rows)->first(fn ($row) => $row[2] === 'Karim Mia');
        $this->assertSame('01812345678', $due[3]);
        $this->assertSame(['180.00', '100.00', '80.00', 'Completed'], array_slice($due, 8));
        $this->assertSame('Cancelled', $rows[1][11]);

        $best = $this->asOwnerOf($this->shop)->get('/api/v1/reports/best-sellers/export?format=csv')->getContent();
        $this->assertStringContainsString('মিনিকেট চাল', $best);

        // A name that a spreadsheet would run as a formula is neutralised.
        $this->sell([[$this->soap, 1]], '50', ['payments' => [], 'due_amount' => '50', 'customer' => ['name' => '=1+1', 'phone' => '01712345678']]);
        $dues = $this->asOwnerOf($this->shop)->get('/api/v1/reports/dues/export?format=csv')->getContent();
        $this->assertStringContainsString("'=1+1", $dues);
    }

    public function test_the_excel_export_is_a_real_workbook_with_numbers_as_numbers_and_phones_as_text(): void
    {
        $this->tradeToday();

        $response = $this->asOwnerOf($this->shop)->get('/api/v1/reports/sales/export?format=xlsx')->assertOk();
        $this->assertSame('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', $response->headers->get('Content-Type'));

        $path = tempnam(sys_get_temp_dir(), 'report').'.xlsx';
        file_put_contents($path, $response->getContent());
        $sheet = IOFactory::load($path)->getActiveSheet();
        @unlink($path);

        $this->assertSame('Sales history', $sheet->getTitle());
        $this->assertSame('Invoice', $sheet->getCell('A1')->getValue());
        $this->assertTrue($sheet->getStyle('A1')->getFont()->getBold());

        $row = collect(range(2, 4))->first(fn ($r) => $sheet->getCell("C{$r}")->getValue() === 'Karim Mia');
        // The phone keeps its leading zero…
        $this->assertSame('01812345678', $sheet->getCell("D{$row}")->getValue());
        $this->assertSame('s', $sheet->getCell("D{$row}")->getDataType());
        // …while money is numeric, so the shopkeeper can add a column up.
        $this->assertSame('n', $sheet->getCell("I{$row}")->getDataType());
        $this->assertEquals(180, $sheet->getCell("I{$row}")->getValue());
        $this->assertEquals(80, $sheet->getCell("K{$row}")->getValue());
    }

    public function test_text_that_looks_like_a_formula_is_not_executed_by_a_spreadsheet(): void
    {
        $this->sell([[$this->soap, 1]], '50', ['payments' => [], 'due_amount' => '50', 'customer' => ['name' => '=HYPERLINK("http://evil.example","x")', 'phone' => '01712345678']]);

        $path = tempnam(sys_get_temp_dir(), 'report').'.xlsx';
        file_put_contents($path, $this->asOwnerOf($this->shop)->get('/api/v1/reports/dues/export?format=xlsx')->getContent());
        $cell = IOFactory::load($path)->getActiveSheet()->getCell('A2');
        @unlink($path);

        $this->assertSame('s', $cell->getDataType(), 'Stored as text, not as a formula.');
        $this->assertSame('=HYPERLINK("http://evil.example","x")', $cell->getValue());
    }

    public function test_every_report_exports_in_every_format(): void
    {
        $this->tradeToday();

        foreach (['summary', 'payment-methods', 'best-sellers', 'low-stock', 'sales', 'dues'] as $report) {
            foreach (['xlsx' => 'PK', 'csv' => "\xEF\xBB\xBF", 'pdf' => '%PDF-'] as $format => $signature) {
                $response = $this->asOwnerOf($this->shop)->get("/api/v1/reports/{$report}/export?format={$format}&range=this_month");
                $response->assertOk();
                $this->assertStringStartsWith($signature, $response->getContent(), "{$report}.{$format}");
            }
        }

        $this->asOwnerOf($this->shop)->get('/api/v1/reports/summary/export?format=docx', ['Accept' => 'application/json'])->assertUnprocessable();
        $this->asOwnerOf($this->shop)->get('/api/v1/reports/secrets/export?format=csv', ['Accept' => 'application/json'])->assertNotFound();
        $this->asOwnerOf($this->shop)->get('/api/v1/reports/summary/export', ['Accept' => 'application/json'])->assertUnprocessable();
    }

    public function test_the_pdf_export_contains_the_figures_and_the_shop_name_in_bangla(): void
    {
        $this->tradeToday();

        $pdf = $this->asOwnerOf($this->shop)->get('/api/v1/reports/summary/export?format=pdf')->assertOk()->getContent();
        $path = tempnam(sys_get_temp_dir(), 'report').'.pdf';
        file_put_contents($path, $pdf);
        $text = (string) shell_exec('pdftotext -layout '.escapeshellarg($path).' - 2>/dev/null');
        @unlink($path);

        if ($text === '') {
            $this->markTestSkipped('pdftotext is not installed; cannot read the PDF text.');
        }

        $this->assertStringContainsString('Sales summary', $text);
        $this->assertStringContainsString('Gross profit', $text);
        $this->assertStringContainsString('115.00', $text);
        $this->assertStringContainsString('355.00', $text);
    }

    public function test_an_export_that_would_be_too_large_is_refused_with_advice(): void
    {
        $this->tradeToday();
        config(['dokani.exports.max_rows' => 2]);

        $this->asOwnerOf($this->shop)->get('/api/v1/reports/sales/export?format=csv', ['Accept' => 'application/json'])
            ->assertUnprocessable()->assertJsonPath('code', 'EXPORT_TOO_LARGE');
    }
}
