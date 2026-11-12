<?php

namespace App\Services\Sales;

use App\Models\Sale;
use Mpdf\Config\ConfigVariables;
use Mpdf\Config\FontVariables;
use Mpdf\Mpdf;
use Symfony\Component\HttpFoundation\Response;

/**
 * Renders an invoice as PDF: A4, or a narrow receipt (80mm / 58mm).
 *
 * mPDF is used because it shapes Bengali text correctly (conjuncts and vowel
 * signs); the bundled Hind Siliguri font matches the mobile app.
 */
class InvoicePdf
{
    public function __construct(private readonly InvoicePresenter $presenter) {}

    public function response(Sale $sale, string $width = 'a4'): Response
    {
        $width = in_array($width, ['a4', '80', '58'], true) ? $width : 'a4';

        return response($this->render($sale, $width), 200, [
            'Content-Type' => 'application/pdf',
            'Content-Disposition' => 'inline; filename="'.$sale->invoice_no.'.pdf"',
            'X-Robots-Tag' => 'noindex, nofollow',
            'Cache-Control' => 'private, no-store',
        ]);
    }

    public function render(Sale $sale, string $width = 'a4'): string
    {
        $invoice = $this->presenter->present($sale);
        $receipt = $width !== 'a4';
        $html = view('invoices.pdf', ['invoice' => $invoice, 'receipt' => $receipt, 'narrow' => $width === '58'])->render();

        if (! $receipt) {
            return $this->document($invoice, 'A4', 15, $html)->Output('', 'S');
        }

        // A receipt is one continuous strip. Lay it out once on a very tall page
        // to learn how long it is, then produce it at exactly that length.
        $measure = $this->document($invoice, [(int) $width, 2000], 3, $html);
        $height = (int) ceil($measure->y) + 6;

        return $this->document($invoice, [(int) $width, $height], 3, $html)->Output('', 'S');
    }

    /**
     * @param  array<string, mixed>  $invoice
     * @param  string|array{0: int, 1: int}  $format  a paper name, or [width, height] in millimetres
     */
    private function document(array $invoice, string|array $format, int $margin, string $html): Mpdf
    {
        $fontDirs = (new ConfigVariables)->getDefaults()['fontDir'];
        $fontData = (new FontVariables)->getDefaults()['fontdata'];

        $mpdf = new Mpdf([
            'mode' => 'utf-8',
            'format' => $format,
            'margin_left' => $margin,
            'margin_right' => $margin,
            'margin_top' => $margin,
            'margin_bottom' => $margin,
            'tempDir' => storage_path('app/mpdf'),
            'fontDir' => array_merge($fontDirs, [resource_path('fonts')]),
            'fontdata' => $fontData + [
                'hindsiliguri' => [
                    'R' => 'HindSiliguri-Regular.ttf',
                    'B' => 'HindSiliguri-SemiBold.ttf',
                    'useOTL' => 0xFF, // OpenType shaping, needed for Bengali
                ],
            ],
            'default_font' => 'hindsiliguri',
        ]);

        $mpdf->SetTitle($invoice['invoice_no']);
        $mpdf->SetAuthor($invoice['shop']['name']);
        $mpdf->WriteHTML($html);

        return $mpdf;
    }
}
