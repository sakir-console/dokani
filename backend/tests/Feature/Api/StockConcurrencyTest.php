<?php

namespace Tests\Feature\Api;

use App\Enums\StockMovementType;
use App\Exceptions\ApiException;
use App\Models\ProductVariant;
use App\Models\StockMovement;
use App\Services\Inventory\StockService;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Real concurrency: separate processes, separate database connections,
 * all taking stock from the same variant at the same moment.
 *
 * Other tests run inside a transaction that is rolled back. This one cannot:
 * the worker processes must see committed data. So it commits for real and
 * rebuilds the schema afterwards.
 */
class StockConcurrencyTest extends TestCase
{
    protected function setUp(): void
    {
        if (! function_exists('pcntl_fork')) {
            $this->markTestSkipped('Needs the pcntl extension.');
        }

        parent::setUp();
    }

    /** Overrides RefreshDatabase: no wrapping transaction for this class. */
    public function beginDatabaseTransaction(): void {}

    protected function tearDown(): void
    {
        // Leave an empty schema for the tests that follow.
        $this->artisan('migrate:fresh');

        parent::tearDown();
    }

    public function test_simultaneous_withdrawals_never_oversell_and_never_lose_an_update(): void
    {
        $shop = $this->createShop();
        $variant = $this->createProduct($shop, [], [['purchase_price' => 1, 'selling_price' => 2, 'stock_quantity' => 5]])->variants[0];

        $workers = 12; // each tries to take 1 of the 5 in stock
        $resultDir = sys_get_temp_dir().'/dokani-race-'.getmypid();
        @mkdir($resultDir);
        DB::disconnect();

        $pids = [];
        for ($i = 0; $i < $workers; $i++) {
            $pid = pcntl_fork();
            if ($pid === 0) {
                // Child: its own connection, as a separate web request would have.
                try {
                    DB::reconnect();
                    $this->tenant()->runFor($shop, fn () => app(StockService::class)
                        ->change($variant->id, StockMovementType::StockOut, '-1', null, ['note' => 'race']));
                    $result = 'ok';
                } catch (ApiException $e) {
                    $result = $e->errorCode;
                } catch (\Throwable $e) {
                    $result = 'error: '.$e::class.': '.$e->getMessage();
                }
                file_put_contents($resultDir.'/'.getmypid(), $result);
                // End the child here, without running PHPUnit's own shutdown a second time.
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

        $succeeded = count(array_keys($results, 'ok', true));
        $refused = count(array_keys($results, 'INSUFFICIENT_STOCK', true));
        $unexpected = array_values(array_diff($results, ['ok', 'INSUFFICIENT_STOCK']));

        DB::reconnect();

        $this->assertSame([], $unexpected, 'No worker may fail for any reason other than insufficient stock.');
        $this->assertSame(5, $succeeded, 'Exactly as many withdrawals succeed as there were units.');
        $this->assertSame($workers - 5, $refused);

        $this->tenant()->runFor($shop, function () use ($variant) {
            $this->assertSame('0.000', ProductVariant::query()->whereKey($variant->id)->value('stock_quantity'));

            $balances = StockMovement::query()->where('type', StockMovementType::StockOut)->orderBy('id')->pluck('balance_after')->all();
            $this->assertSame(['4.000', '3.000', '2.000', '1.000', '0.000'], $balances, 'Each withdrawal saw the result of the one before it.');
        });
    }
}
