<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\CustomerResource;
use App\Http\Resources\SaleResource;
use App\Services\Reports\ReportExporter;
use App\Services\Reports\ReportRange;
use App\Services\Reports\ReportService;
use App\Services\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Symfony\Component\HttpFoundation\Response;

class ReportController extends Controller
{
    /** The period asked for, as whole days in the shop's time zone. */
    private function range(Request $request, TenantContext $tenant): ReportRange
    {
        $input = $request->validate([
            'range' => ['sometimes', Rule::in(ReportRange::KEYS)],
            'from' => ['sometimes', 'nullable', 'date_format:Y-m-d'],
            'to' => ['sometimes', 'nullable', 'date_format:Y-m-d'],
        ]);

        return ReportRange::resolve($input, $tenant->shop());
    }

    public function summary(Request $request, ReportService $reports, TenantContext $tenant): JsonResponse
    {
        $range = $this->range($request, $tenant);

        return response()->json(['data' => $reports->summary($range), 'meta' => ['range' => $range->toArray()]]);
    }

    public function daily(Request $request, ReportService $reports, TenantContext $tenant): JsonResponse
    {
        $range = $this->range($request, $tenant);

        return response()->json(['data' => $reports->daily($range), 'meta' => ['range' => $range->toArray()]]);
    }

    public function paymentMethods(Request $request, ReportService $reports, TenantContext $tenant): JsonResponse
    {
        $range = $this->range($request, $tenant);

        return response()->json(['data' => $reports->paymentMethods($range), 'meta' => ['range' => $range->toArray()]]);
    }

    public function bestSellers(Request $request, ReportService $reports, TenantContext $tenant): JsonResponse
    {
        $range = $this->range($request, $tenant);
        $options = $request->validate([
            'by' => ['sometimes', Rule::in(['quantity', 'revenue'])],
            'limit' => ['sometimes', 'integer', 'min:1', 'max:100'],
        ]);

        return response()->json([
            'data' => $reports->bestSellers($range, $options['by'] ?? 'quantity', (int) ($options['limit'] ?? 20)),
            'meta' => ['range' => $range->toArray()],
        ]);
    }

    public function lowStock(Request $request, ReportService $reports): JsonResponse
    {
        $page = $reports->lowStock($request->integer('per_page', 50));

        return response()->json([
            'data' => $page->items(),
            'meta' => ['current_page' => $page->currentPage(), 'last_page' => $page->lastPage(), 'total' => $page->total()],
        ]);
    }

    public function sales(Request $request, ReportService $reports, TenantContext $tenant): JsonResponse
    {
        $range = $this->range($request, $tenant);
        $page = $reports->sales($range)->paginate(min($request->integer('per_page', 30), 100));

        return response()->json([
            'data' => SaleResource::collection($page->items())->resolve($request),
            'meta' => ['current_page' => $page->currentPage(), 'last_page' => $page->lastPage(), 'total' => $page->total(), 'range' => $range->toArray()],
        ]);
    }

    public function dues(Request $request, ReportService $reports): JsonResponse
    {
        $page = $reports->dues()->paginate(min($request->integer('per_page', 30), 100));

        return response()->json([
            'data' => CustomerResource::collection($page->items())->resolve($request),
            'meta' => ['current_page' => $page->currentPage(), 'last_page' => $page->lastPage(), 'total' => $page->total()] + $reports->duesTotal(),
        ]);
    }

    public function export(Request $request, string $report, ReportExporter $exporter, TenantContext $tenant): Response
    {
        $format = $request->validate(['format' => ['required', Rule::in(ReportExporter::FORMATS)]])['format'];
        abort_unless(in_array($report, ReportExporter::REPORTS, true), 404);

        return $exporter->download($exporter->table($report, $this->range($request, $tenant)), $format);
    }
}
