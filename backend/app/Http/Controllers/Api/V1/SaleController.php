<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\PaymentMethod;
use App\Enums\SaleStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\StoreSaleRequest;
use App\Http\Resources\SaleResource;
use App\Models\Sale;
use App\Services\Sales\CreateSale;
use App\Services\Sales\InvoicePdf;
use App\Services\Sales\VoidSale;
use App\Services\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Carbon;
use Illuminate\Validation\Rule;
use Symfony\Component\HttpFoundation\Response;

class SaleController extends Controller
{
    private const DETAIL = ['items', 'payments', 'customer', 'invoice'];

    public function index(Request $request, TenantContext $tenant): AnonymousResourceCollection
    {
        $filters = $request->validate([
            'from' => ['sometimes', 'date'],
            'to' => ['sometimes', 'date'],
            'customer_id' => ['sometimes', 'integer'],
            'status' => ['sometimes', Rule::enum(SaleStatus::class)],
            'payment_method' => ['sometimes', Rule::enum(PaymentMethod::class)],
            'has_due' => ['sometimes', 'boolean'],
            'q' => ['sometimes', 'nullable', 'string', 'max:30'],
        ]);

        // Dates are whole days in the shop's own time zone.
        $timezone = $tenant->shop()->timezone;
        $from = isset($filters['from']) ? Carbon::parse($filters['from'], $timezone)->startOfDay()->utc() : null;
        $to = isset($filters['to']) ? Carbon::parse($filters['to'], $timezone)->endOfDay()->utc() : null;

        $sales = Sale::query()
            ->with(['customer', 'invoice'])
            ->when($from, fn ($q) => $q->where('sold_at', '>=', $from))
            ->when($to, fn ($q) => $q->where('sold_at', '<=', $to))
            ->when($filters['customer_id'] ?? null, fn ($q, $id) => $q->where('customer_id', $id))
            ->when($filters['status'] ?? null, fn ($q, $status) => $q->where('status', $status))
            ->when($filters['payment_method'] ?? null, fn ($q, $method) => $q->whereHas('payments', fn ($p) => $p->where('method', $method)))
            ->when($request->boolean('has_due'), fn ($q) => $q->where('due_amount', '>', 0))
            ->when($filters['q'] ?? null, fn ($q, $term) => $q->where('invoice_no', 'like', '%'.addcslashes($term, '%_\\').'%'))
            ->latest('sold_at')->latest('id')
            ->paginate(min($request->integer('per_page', 30), 100));

        return SaleResource::collection($sales);
    }

    public function store(StoreSaleRequest $request, CreateSale $createSale, TenantContext $tenant): JsonResponse
    {
        $canOverridePrice = $tenant->membership()?->role->can('pos.price_override') ?? false;

        [$sale, $created] = $createSale->handle($request->validated(), $request->user(), $canOverridePrice);

        // 201 for a new sale, 200 when the same sale had already been recorded.
        return (new SaleResource($sale->load(self::DETAIL)))->response()->setStatusCode($created ? 201 : 200);
    }

    public function show(Sale $sale): SaleResource
    {
        return new SaleResource($sale->load(self::DETAIL));
    }

    public function void(Request $request, Sale $sale, VoidSale $voidSale): SaleResource
    {
        $data = $request->validate(['reason' => ['required', 'string', 'max:255']]);

        return new SaleResource($voidSale->handle($sale, $data['reason'], $request->user())->load(self::DETAIL));
    }

    public function pdf(Request $request, Sale $sale, InvoicePdf $pdf): Response
    {
        return $pdf->response($sale, $request->string('width', 'a4')->toString());
    }
}
