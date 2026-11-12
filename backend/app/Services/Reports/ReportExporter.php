<?php

namespace App\Services\Reports;

use App\Exceptions\ApiException;
use App\Exports\ReportTableExport;
use App\Models\Customer;
use App\Models\Sale;
use App\Services\Tenancy\TenantContext;
use Maatwebsite\Excel\Excel as ExcelFormat;
use Maatwebsite\Excel\Facades\Excel;
use Mpdf\Config\ConfigVariables;
use Mpdf\Config\FontVariables;
use Mpdf\Mpdf;
use Symfony\Component\HttpFoundation\Response;

/**
 * Turns a report into a downloadable file: Excel, CSV or PDF.
 * All three are written from the same ReportTable, so they always agree.
 */
class ReportExporter
{
    public const REPORTS = ['summary', 'payment-methods', 'best-sellers', 'low-stock', 'sales', 'dues'];

    public const FORMATS = ['xlsx', 'csv', 'pdf'];

    public function __construct(private readonly ReportService $reports, private readonly TenantContext $tenant) {}

    public function table(string $report, ReportRange $range): ReportTable
    {
        $shop = $this->tenant->shop()->name;
        $limit = (int) config('dokani.exports.max_rows');

        return match ($report) {
            'summary' => $this->summary($shop, $range),
            'payment-methods' => $this->paymentMethods($shop, $range),
            'best-sellers' => $this->bestSellers($shop, $range),
            'low-stock' => $this->lowStock($shop, $limit),
            'sales' => $this->sales($shop, $range, $limit),
            'dues' => $this->dues($shop, $limit),
        };
    }

    public function download(ReportTable $table, string $format): Response
    {
        [$body, $type, $extension] = match ($format) {
            'xlsx' => [Excel::raw(new ReportTableExport($table), ExcelFormat::XLSX), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'xlsx'],
            'csv' => [$this->csv($table), 'text/csv; charset=UTF-8', 'csv'],
            'pdf' => [$this->pdf($table), 'application/pdf', 'pdf'],
        };

        return response($body, 200, [
            'Content-Type' => $type,
            'Content-Disposition' => 'attachment; filename="'.$table->fileName($extension).'"',
            'Cache-Control' => 'private, no-store',
        ]);
    }

    /**
     * Written directly rather than through the spreadsheet library, so amounts
     * stay exactly as stored ("180.00", not "180").
     */
    private function csv(ReportTable $table): string
    {
        $stream = fopen('php://temp', 'r+');
        // The byte-order mark makes Excel read the file as UTF-8, so Bangla names are not garbled.
        fwrite($stream, "\xEF\xBB\xBF");

        foreach ([$table->headings, ...$table->rows] as $row) {
            fputcsv($stream, array_map($this->csvCell(...), $row), ',', '"', '', "\r\n");
        }

        rewind($stream);
        $csv = stream_get_contents($stream);
        fclose($stream);

        return $csv;
    }

    /**
     * Text starting with = + - @ would be run as a formula when the file is
     * opened in a spreadsheet; a leading apostrophe makes it plain text.
     * Real negative amounts are left alone.
     */
    private function csvCell(string|int|null $value): string
    {
        $value = (string) $value;

        return preg_match('/^[=+\-@]/', $value) === 1 && preg_match('/^-?\d+(\.\d+)?$/', $value) !== 1
            ? "'".$value
            : $value;
    }

    private function pdf(ReportTable $table): string
    {
        $mpdf = new Mpdf([
            'mode' => 'utf-8',
            // Wide tables get a landscape page.
            'format' => count($table->headings) > 6 ? 'A4-L' : 'A4',
            'margin_left' => 12, 'margin_right' => 12, 'margin_top' => 12, 'margin_bottom' => 14,
            'tempDir' => storage_path('app/mpdf'),
            'fontDir' => array_merge((new ConfigVariables)->getDefaults()['fontDir'], [resource_path('fonts')]),
            'fontdata' => (new FontVariables)->getDefaults()['fontdata'] + [
                'hindsiliguri' => ['R' => 'HindSiliguri-Regular.ttf', 'B' => 'HindSiliguri-SemiBold.ttf', 'useOTL' => 0xFF],
            ],
            'default_font' => 'hindsiliguri',
        ]);

        $mpdf->SetTitle($table->title);
        $mpdf->SetFooter('{PAGENO} / {nbpg}');
        $mpdf->WriteHTML(view('reports.pdf', ['table' => $table])->render());

        return $mpdf->Output('', 'S');
    }

    // --- Tables --------------------------------------------------------------

    private function summary(string $shop, ReportRange $range): ReportTable
    {
        $s = $this->reports->summary($range);

        return new ReportTable('summary', 'Sales summary', $shop, $range->label(), ['Figure', 'Value'], [
            ['Orders', $s['orders']],
            ['Items sold', $this->trim($s['items_sold'])],
            ['Total sales', $s['total_sales']],
            ['Total paid', $s['total_paid']],
            ['Total due', $s['total_due']],
            ['Total discounts', $s['total_discounts']],
            ['Additional charges', $s['additional_charges']],
            ['Revenue (goods, after discounts)', $s['revenue']],
            ['Cost of goods sold', $s['cost_of_goods']],
            ['Gross profit', $s['gross_profit']],
            ['Due collected in this period', $s['due_collected']],
            ['Cancelled orders', $s['cancelled_orders']],
            ['Cancelled amount', $s['cancelled_amount']],
        ], [1]);
    }

    private function paymentMethods(string $shop, ReportRange $range): ReportTable
    {
        $report = $this->reports->paymentMethods($range);

        $rows = array_map(fn (array $m) => [$m['label'], $m['sales'], $m['due_collections'], $m['refunds'], $m['net']], $report['methods']);
        $rows[] = ['Total', $report['totals']['sales'], $report['totals']['due_collections'], $report['totals']['refunds'], $report['totals']['net']];
        $rows[] = ['Sold on due (not received)', $report['sold_on_due'], null, null, null];

        return new ReportTable('payment-methods', 'Sales by payment method', $shop, $range->label(),
            ['Method', 'Sales', 'Due collections', 'Refunds', 'Net received'], $rows, [1, 2, 3, 4]);
    }

    private function bestSellers(string $shop, ReportRange $range): ReportTable
    {
        $rows = $this->reports->bestSellers($range, 'quantity', 100)->map(fn (array $row) => [
            trim($row['product_name'].($row['variant_name'] ? ' — '.$row['variant_name'] : '')),
            $this->trim($row['quantity']), $row['unit_name'], $row['revenue'], $row['profit'],
        ])->all();

        return new ReportTable('best-sellers', 'Best-selling products', $shop, $range->label(),
            ['Product', 'Quantity', 'Unit', 'Revenue', 'Profit'], $rows, [1, 3, 4]);
    }

    private function lowStock(string $shop, int $limit): ReportTable
    {
        $rows = $this->reports->lowStockAll($limit)->map(fn (array $row) => [
            trim($row['product_name'].($row['variant_name'] ? ' — '.$row['variant_name'] : '')),
            $this->trim($row['stock_quantity']), $row['unit_name'], $this->trim($row['threshold']),
            $row['status'] === 'out' ? 'Out of stock' : 'Low',
        ])->all();

        return new ReportTable('low-stock', 'Low-stock products', $shop, null,
            ['Product', 'In stock', 'Unit', 'Alert at', 'Status'], $rows, [1, 3]);
    }

    private function sales(string $shop, ReportRange $range, int $limit): ReportTable
    {
        $query = $this->reports->sales($range);
        $this->assertWithinLimit($query->count(), $limit);

        $timezone = $this->tenant->shop()->timezone;
        $rows = $query->get()->map(fn (Sale $sale) => [
            $sale->invoice_no,
            $sale->sold_at->copy()->timezone($timezone)->format('Y-m-d H:i'),
            $sale->customer?->name,
            $sale->customer?->phone,
            $this->trim($sale->total_items),
            $sale->subtotal, $sale->discount_amount, $sale->additional_charge,
            $sale->grand_total, $sale->paid_amount, $sale->due_amount,
            $sale->isVoided() ? 'Cancelled' : 'Completed',
        ])->all();

        return new ReportTable('sales', 'Sales history', $shop, $range->label(),
            ['Invoice', 'Date', 'Customer', 'Phone', 'Items', 'Subtotal', 'Discount', 'Charge', 'Total', 'Paid', 'Due', 'Status'],
            $rows, [4, 5, 6, 7, 8, 9, 10]);
    }

    private function dues(string $shop, int $limit): ReportTable
    {
        $query = $this->reports->dues();
        $this->assertWithinLimit($query->count(), $limit);

        $rows = $query->get()->map(fn (Customer $customer) => [
            $customer->name, $customer->phone, $customer->current_due,
            $customer->last_purchase_at?->copy()->timezone($this->tenant->shop()->timezone)->format('Y-m-d'),
        ])->all();
        $rows[] = ['Total', null, $this->reports->duesTotal()['total_due'], null];

        return new ReportTable('dues', 'Customer dues', $shop, 'As of '.now($this->tenant->shop()->timezone)->format('j M Y'),
            ['Customer', 'Phone', 'Due', 'Last purchase'], $rows, [2]);
    }

    private function assertWithinLimit(int $count, int $limit): void
    {
        if ($count > $limit) {
            throw new ApiException('EXPORT_TOO_LARGE', __('This report has :count rows. Choose a shorter period (at most :limit rows).', [
                'count' => $count, 'limit' => $limit,
            ]), 422);
        }
    }

    /** "25.500" → "25.5", "10.000" → "10" */
    private function trim(string $quantity): string
    {
        return str_contains($quantity, '.') ? rtrim(rtrim($quantity, '0'), '.') : $quantity;
    }
}
