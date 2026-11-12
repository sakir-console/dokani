<?php

namespace Tests\Feature\Api;

use App\Exceptions\ApiException;
use App\Models\Customer;
use App\Models\ProductVariant;
use App\Models\Sale;
use App\Models\Shop;
use App\Services\Sales\CreateSale;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Real concurrency for sales: separate processes, each with its own database
 * connection, all hitting the same shop at the same moment.
 *
 * Like StockConcurrencyTest it commits for real and rebuilds the schema after.
 */
class SaleConcurrencyTest extends TestCase
{
    protected function setUp(): void
    {
        if (! function_exists('pcntl_fork')) {
            $this->markTestSkipped('Needs the pcntl extension.');
        }

        parent::setUp();
    }

    public function beginDatabaseTransaction(): void {}

    protected function tearDown(): void
    {
        $this->artisan('migrate:fresh');

        parent::tearDown();
    }

    /**
     * Runs one sale per payload in parallel processes.
     *
     * @param  list<array<string, mixed>>  $payloads
     * @return list<string> 'created:<invoice>', 'duplicate:<invoice>', or an error code, per worker
     */
    private function sellInParallel(Shop $shop, array $payloads): array
    {
        $resultDir = sys_get_temp_dir().'/dokani-sale-race-'.getmypid();
        @mkdir($resultDir);
        $owner = $shop->owner;
        DB::disconnect();

        $pids = [];
        foreach ($payloads as $payload) {
            $pid = pcntl_fork();
            if ($pid === 0) {
                try {
                    DB::reconnect();
                    [$sale, $created] = $this->tenant()->runFor($shop, fn () => app(CreateSale::class)->handle($payload, $owner, true));
                    $result = ($created ? 'created:' : 'duplicate:').$sale->invoice_no;
                } catch (ApiException $e) {
                    $result = $e->errorCode;
                } catch (\Throwable $e) {
                    $result = 'error: '.$e::class.': '.$e->getMessage();
                }
                file_put_contents($resultDir.'/'.getmypid(), $result);
                posix_kill(getmypid(), SIGKILL);
            }
            $pids[] = $pid;
        }

        $results = [];
        foreach ($pids as $pid) {
            pcntl_waitpid($pid, $status);
            $results[] = @file_get_contents($resultDir.'/'.$pid) ?: 'no result';
            @unlink($resultDir.'/'.$pid);
        }
        @rmdir($resultDir);
        DB::reconnect();

        return $results;
    }

    public function test_simultaneous_sales_never_oversell_and_get_distinct_consecutive_invoice_numbers(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop, [], [['purchase_price' => '50', 'selling_price' => '60', 'stock_quantity' => 4]])->variants[0];

        // Ten cashiers each try to sell one of the four in stock, at once.
        $results = $this->sellInParallel($shop, array_map(
            fn () => $this->salePayload([[$variant->id, 1]], '60'),
            range(1, 10),
        ));

        $created = array_values(array_filter($results, fn ($r) => str_starts_with($r, 'created:')));
        $unexpected = array_values(array_filter($results, fn ($r) => ! str_starts_with($r, 'created:') && $r !== 'INSUFFICIENT_STOCK'));

        $this->assertSame([], $unexpected);
        $this->assertCount(4, $created, 'Only as many sales succeed as there is stock.');

        sort($created);
        $this->assertSame(['created:INV-000001', 'created:INV-000002', 'created:INV-000003', 'created:INV-000004'], $created, 'No duplicate and no skipped invoice number.');

        $this->tenant()->runFor($shop, function () use ($variant) {
            $this->assertSame('0.000', ProductVariant::query()->whereKey($variant->id)->value('stock_quantity'));
            $this->assertSame(4, Sale::query()->count());
        });
    }

    public function test_the_same_sale_sent_many_times_at_once_is_recorded_once(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop, [], [['purchase_price' => '50', 'selling_price' => '60', 'stock_quantity' => 100]])->variants[0];
        $payload = $this->salePayload([[$variant->id, 1]], '60', ['client_uuid' => (string) Str::uuid()]);

        // A flaky connection makes the app send the same sale eight times.
        $results = $this->sellInParallel($shop, array_fill(0, 8, $payload));

        $this->assertCount(1, array_filter($results, fn ($r) => str_starts_with($r, 'created:')), 'Exactly one request creates the sale.');
        $this->assertCount(7, array_filter($results, fn ($r) => $r === 'duplicate:INV-000001'), 'The rest are answered with that same sale.');

        $this->tenant()->runFor($shop, function () use ($variant) {
            $this->assertSame(1, Sale::query()->count());
            $this->assertSame('99.000', ProductVariant::query()->whereKey($variant->id)->value('stock_quantity'));
        });
    }

    public function test_simultaneous_due_sales_to_one_customer_all_reach_the_ledger(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop, [], [['purchase_price' => '50', 'selling_price' => '100', 'stock_quantity' => 100]])->variants[0];

        // Six sales on credit to the same new phone number at the same instant.
        $results = $this->sellInParallel($shop, array_map(
            fn () => $this->salePayload([[$variant->id, 1]], '100', [
                'payments' => [], 'due_amount' => '100', 'customer' => ['name' => 'Rahim', 'phone' => '01712345678'],
            ]),
            range(1, 6),
        ));

        $this->assertCount(6, array_filter($results, fn ($r) => str_starts_with($r, 'created:')), implode(', ', $results));

        $this->tenant()->runFor($shop, function () {
            $customer = Customer::query()->sole(); // one customer, not six
            $this->assertSame('600.00', $customer->current_due, 'No due was lost to a race.');
            $this->assertSame(6, $customer->ledger()->count());
            $this->assertSame('600.00', $customer->ledger()->latest('id')->value('balance_after'));
        });
    }
}
