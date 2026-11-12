<?php

namespace App\Services\Sync;

use App\Enums\PaymentMethod;
use App\Exceptions\ApiException;
use App\Http\Requests\Api\V1\ProductRequest;
use App\Http\Requests\Api\V1\StoreSaleRequest;
use App\Models\Customer;
use App\Models\User;
use App\Services\Customers\CollectDue;
use App\Services\Sales\CreateSale;
use App\Support\Phone;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;
use Throwable;

/**
 * Takes what a phone recorded while offline and stores it.
 *
 * Every record is handled on its own, in its own transaction: one bad record
 * never blocks the others, and each gets an explicit answer the phone keeps —
 *
 *   created    stored now
 *   duplicate  already stored by an earlier attempt (the retry is harmless)
 *   failed     not stored, with a code and a message the phone shows the user
 *
 * The phone removes a record from its queue only after "created" or
 * "duplicate". Nothing is ever dropped silently.
 */
class PushService
{
    public function __construct(private readonly CreateSale $createSale, private readonly CollectDue $collectDue) {}

    /**
     * @param  list<mixed>  $sales
     * @return list<array<string, mixed>>
     */
    public function pushSales(array $sales, User $actor, ?int $deviceId): array
    {
        $rules = $this->saleRules();

        return array_map(function ($record) use ($rules, $actor, $deviceId) {
            return $this->attempt($record, $rules, function (array $data) use ($actor, $deviceId) {
                if (isset($data['customer']['phone'])) {
                    $data['customer']['phone'] = Phone::normalize($data['customer']['phone']);
                }

                [$sale, $created] = $this->createSale->handleOffline($data, $actor, $deviceId);
                $sale->loadMissing('invoice');

                return [$created, [
                    'id' => $sale->id,
                    'invoice_no' => $sale->invoice_no,
                    'invoice_url' => $sale->invoice?->publicUrl(),
                    'has_stock_conflict' => $sale->has_stock_conflict,
                ]];
            });
        }, array_values($sales));
    }

    /**
     * @param  list<mixed>  $collections
     * @return list<array<string, mixed>>
     */
    public function pushDueCollections(array $collections, User $actor): array
    {
        $rules = [
            'client_uuid' => ['required', 'uuid'],
            'customer_id' => ['required_without:customer_phone', 'nullable', 'integer'],
            'customer_phone' => ['required_without:customer_id', 'nullable', 'string'],
            'amount' => ['required', 'numeric', 'decimal:0,2', 'gt:0', 'max:999999999.99'],
            'method' => ['required', Rule::enum(PaymentMethod::class)],
            'transaction_id' => ['sometimes', 'nullable', 'string', 'max:100'],
            'paid_at' => ['sometimes', 'nullable', 'date'],
        ];

        return array_map(function ($record) use ($rules, $actor) {
            return $this->attempt($record, $rules, function (array $data) use ($actor) {
                // By id when the phone knew the customer; by phone when the customer
                // was first created inside an offline sale pushed just before this.
                $customer = isset($data['customer_id'])
                    ? Customer::query()->withTrashed()->find($data['customer_id'])
                    : Customer::query()->withTrashed()->where('phone', Phone::normalize($data['customer_phone']))->first();

                if ($customer === null) {
                    throw new ApiException('CUSTOMER_NOT_FOUND', __('The customer for this payment was not found.'), 404);
                }

                [$payment, $created] = $this->collectDue->handle($customer, $data, $actor, offline: true);

                return [$created, ['id' => $payment->id, 'customer_id' => $customer->id, 'current_due' => $customer->refresh()->current_due]];
            });
        }, array_values($collections));
    }

    /**
     * Validates and stores one record, turning every outcome into a result row.
     *
     * @param  array<string, mixed>  $rules
     * @param  callable(array<string, mixed>): array{0: bool, 1: array<string, mixed>}  $store
     * @return array<string, mixed>
     */
    private function attempt(mixed $record, array $rules, callable $store): array
    {
        $uuid = is_array($record) && is_string($record['client_uuid'] ?? null) ? $record['client_uuid'] : null;

        if (! is_array($record)) {
            return $this->failed($uuid, 'VALIDATION_FAILED', __('This record could not be read.'));
        }

        $validator = Validator::make($record, $rules);
        if ($validator->fails()) {
            return $this->failed($uuid, 'VALIDATION_FAILED', $validator->errors()->first());
        }

        try {
            [$created, $server] = $store($validator->validated());

            return ['client_uuid' => $uuid, 'status' => $created ? 'created' : 'duplicate', 'server' => $server];
        } catch (ApiException $e) {
            return $this->failed($uuid, $e->errorCode, $e->getMessage());
        } catch (Throwable $e) {
            // Logged for us; the phone keeps the record and will show it as failed.
            report($e);

            return $this->failed($uuid, 'SERVER_ERROR', __('The server could not save this record. It is still on your phone.'));
        }
    }

    /** @return array<string, mixed> */
    private function failed(?string $uuid, string $code, string $message): array
    {
        return ['client_uuid' => $uuid, 'status' => 'failed', 'code' => $code, 'message' => $message];
    }

    /** The online sale rules, relaxed where an offline sale must still be accepted. */
    private function saleRules(): array
    {
        $rules = (new StoreSaleRequest)->rules();

        // The customer may have been deleted on the server since the phone last synced.
        $rules['customer_id'] = ['sometimes', 'nullable', 'integer'];
        $rules['offline_ref'] = ['sometimes', 'nullable', 'string', 'max:40'];
        // The price on the phone at the time of sale is required: it is what the customer paid.
        $rules['items.*.unit_price'] = ['required', ...ProductRequest::MONEY];

        return $rules;
    }
}
