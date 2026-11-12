<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\PaymentMethod;
use App\Exceptions\ApiException;
use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\CustomerRequest;
use App\Http\Resources\CustomerResource;
use App\Http\Resources\LedgerEntryResource;
use App\Http\Resources\PaymentResource;
use App\Http\Resources\SaleResource;
use App\Models\Customer;
use App\Rules\BangladeshPhone;
use App\Services\Customers\CollectDue;
use App\Services\Customers\CustomerService;
use App\Support\Dec;
use App\Support\Phone;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\Rule;

class CustomerController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        $term = trim($request->string('q')->toString());
        $like = '%'.addcslashes($term, '%_\\').'%';
        // A search typed as +880… or with Bangla digits still finds 01….
        $phoneLike = '%'.addcslashes(Phone::normalize($term) ?? $term, '%_\\').'%';

        $customers = Customer::query()
            ->when($term !== '', fn ($q) => $q->where(fn ($q) => $q->where('name', 'like', $like)->orWhere('phone', 'like', $phoneLike)))
            ->when($request->boolean('has_due'), fn ($q) => $q->where('current_due', '>', 0))
            // People who owe the most first when looking at dues; otherwise by name.
            ->when($request->boolean('has_due'), fn ($q) => $q->orderByDesc('current_due'), fn ($q) => $q->orderBy('name'))
            ->paginate(min($request->integer('per_page', 30), 100));

        return CustomerResource::collection($customers);
    }

    public function store(CustomerRequest $request, CustomerService $customers): JsonResponse
    {
        $customer = $customers->create($request->validated(), $request->user());

        return (new CustomerResource($customer))->response()->setStatusCode(201);
    }

    /**
     * Exact phone match inside this shop. Used at checkout: type the number,
     * see the name, or learn that a new customer has to be created.
     */
    public function lookup(Request $request): CustomerResource
    {
        $data = $request->validate(['phone' => ['required', 'string', new BangladeshPhone]]);

        $customer = Customer::query()->where('phone', Phone::normalize($data['phone']))->first();

        if ($customer === null) {
            throw new ApiException('CUSTOMER_NOT_FOUND', __('No customer has this mobile number yet.'), 404);
        }

        return new CustomerResource($customer);
    }

    public function show(Customer $customer): CustomerResource
    {
        return new CustomerResource($customer);
    }

    public function update(CustomerRequest $request, Customer $customer): CustomerResource
    {
        $customer->update($request->validated());

        return new CustomerResource($customer);
    }

    public function destroy(Customer $customer): JsonResponse
    {
        if (! Dec::of($customer->current_due)->isZero()) {
            throw ApiException::conflict('CUSTOMER_HAS_DUE', __('This customer still has a balance and cannot be deleted.'));
        }

        $customer->delete();

        return response()->json(null, 204);
    }

    public function ledger(Request $request, Customer $customer): AnonymousResourceCollection
    {
        return LedgerEntryResource::collection(
            $customer->ledger()->with(['sale:id,invoice_no', 'payment:id,method'])->latest('id')
                ->paginate(min($request->integer('per_page', 30), 100))
        );
    }

    public function sales(Request $request, Customer $customer): AnonymousResourceCollection
    {
        return SaleResource::collection(
            $customer->sales()->with(['customer', 'invoice'])->latest('sold_at')->latest('id')
                ->paginate(min($request->integer('per_page', 30), 100))
        );
    }

    public function payments(Request $request, Customer $customer): AnonymousResourceCollection
    {
        return PaymentResource::collection(
            $customer->payments()->with('sale:id,invoice_no')->latest('paid_at')->latest('id')
                ->paginate(min($request->integer('per_page', 30), 100))
        );
    }

    public function collectDue(Request $request, Customer $customer, CollectDue $collect): JsonResponse
    {
        $data = $request->validate([
            'client_uuid' => ['required', 'uuid'],
            'amount' => ['required', 'numeric', 'decimal:0,2', 'gt:0', 'max:999999999.99'],
            'method' => ['required', Rule::enum(PaymentMethod::class)],
            'transaction_id' => ['sometimes', 'nullable', 'string', 'max:100'],
            'reference' => ['sometimes', 'nullable', 'string', 'max:190'],
        ]);

        [$payment, $created] = $collect->handle($customer, $data, $request->user());

        return response()->json([
            'data' => (new PaymentResource($payment))->resolve($request),
            'meta' => ['customer' => (new CustomerResource($customer->refresh()))->resolve($request)],
        ], $created ? 201 : 200);
    }
}
