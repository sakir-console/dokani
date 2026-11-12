<?php

namespace App\Http\Controllers;

use App\Models\Invoice;
use App\Models\Sale;
use App\Services\Sales\InvoicePdf;
use App\Services\Sales\InvoicePresenter;
use App\Services\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

/**
 * Read-only invoice for whoever holds the link from the receipt's QR code.
 *
 * The 256-bit random token is the only credential: no login, no phone number,
 * no database ids. These routes are the single place outside the admin panel
 * that reads shop data without a signed-in shop user, so the lookup is by
 * token only and the shop is then fixed to the invoice's own shop.
 */
class PublicInvoiceController extends Controller
{
    public function show(string $token, InvoicePresenter $presenter, TenantContext $tenant): Response
    {
        return response()
            ->view('invoices.public', ['invoice' => $this->present($token, $presenter, $tenant), 'token' => $token])
            ->header('X-Robots-Tag', 'noindex, nofollow')
            ->header('Cache-Control', 'private, no-store')
            ->header('Referrer-Policy', 'no-referrer');
    }

    public function json(string $token, InvoicePresenter $presenter, TenantContext $tenant): JsonResponse
    {
        $invoice = $this->present($token, $presenter, $tenant);
        $invoice['sold_at'] = $invoice['sold_at']->toIso8601String();

        return response()->json(['data' => $invoice])
            ->header('X-Robots-Tag', 'noindex, nofollow')
            ->header('Cache-Control', 'private, no-store');
    }

    public function pdf(string $token, InvoicePdf $pdf, TenantContext $tenant): Response
    {
        $invoice = $this->find($token, $tenant);

        return $tenant->runFor($invoice->shop, fn () => $pdf->response(Sale::query()->findOrFail($invoice->sale_id)));
    }

    /** @return array<string, mixed> */
    private function present(string $token, InvoicePresenter $presenter, TenantContext $tenant): array
    {
        $invoice = $this->find($token, $tenant);

        // From here on everything is scoped to the invoice's own shop, like any signed-in request.
        return $tenant->runFor($invoice->shop, fn () => $presenter->present(Sale::query()->findOrFail($invoice->sale_id)));
    }

    private function find(string $token, TenantContext $tenant): Invoice
    {
        // Tokens are exactly 43 base64url characters; anything else cannot match.
        if (preg_match('/^[A-Za-z0-9_-]{43}$/', $token) !== 1) {
            throw new NotFoundHttpException;
        }

        $invoice = $tenant->withoutTenancy(fn () => Invoice::query()->with('shop')->where('public_token', $token)->first());

        if ($invoice === null || $invoice->shop === null) {
            throw new NotFoundHttpException;
        }

        return $invoice;
    }
}
