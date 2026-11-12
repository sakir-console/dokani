<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\SaleResource;
use App\Services\Reports\DashboardService;
use App\Services\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class DashboardController extends Controller
{
    public function __invoke(Request $request, DashboardService $dashboard, TenantContext $tenant): JsonResponse
    {
        $seesProfit = $tenant->membership()?->role->can('reports.view') ?? false;
        $today = $dashboard->today();

        if (! $seesProfit) {
            unset($today['profit']);
        }

        return response()->json(['data' => [
            'today' => $today,
            'stock' => $dashboard->stock(),
            'total_customer_due' => $dashboard->totalCustomerDue(),
            'customers_with_due' => $dashboard->customersWithDue(),
            'recent_sales' => SaleResource::collection($dashboard->recentSales())->resolve($request),
        ]]);
    }
}
