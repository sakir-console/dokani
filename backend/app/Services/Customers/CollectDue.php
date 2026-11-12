<?php

namespace App\Services\Customers;

use App\Enums\LedgerType;
use App\Enums\PaymentMethod;
use App\Enums\PaymentType;
use App\Exceptions\ApiException;
use App\Models\Customer;
use App\Models\Payment;
use App\Models\User;
use App\Support\Dec;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Facades\DB;

/**
 * A customer pays off some or all of what they owe.
 * One transaction: payment row, ledger credit, balance update.
 */
class CollectDue
{
    public function __construct(private readonly LedgerService $ledger) {}

    /**
     * @param  array{client_uuid: string, amount: mixed, method: string, transaction_id?: ?string, reference?: ?string, paid_at?: ?string}  $data
     * @return array{0: Payment, 1: bool} the payment, and whether this call created it
     */
    public function handle(Customer $customer, array $data, User $actor): array
    {
        // Sent twice (a retry after a dropped connection)? Return the first result.
        if ($existing = Payment::query()->where('client_uuid', $data['client_uuid'])->first()) {
            return [$existing, false];
        }

        try {
            return DB::transaction(function () use ($customer, $data, $actor) {
                $locked = Customer::query()->lockForUpdate()->findOrFail($customer->id);

                if ($existing = Payment::query()->where('client_uuid', $data['client_uuid'])->first()) {
                    return [$existing, false];
                }

                $amount = Dec::of($data['amount']);
                $due = Dec::of($locked->current_due);

                if ($amount->isGreaterThan($due)) {
                    $message = $due->isPositive()
                        ? __('The customer owes :due. You cannot collect more than that.', ['due' => Dec::money($due)])
                        : __('This customer has no due.');

                    throw new ApiException('AMOUNT_EXCEEDS_DUE', $message, 422, ['amount' => [$message]]);
                }

                $payment = new Payment;
                $payment->client_uuid = $data['client_uuid'];
                $payment->customer_id = $locked->id;
                $payment->type = PaymentType::DueCollection;
                $payment->method = PaymentMethod::from($data['method']);
                $payment->amount = Dec::money($amount);
                $payment->transaction_id = $data['transaction_id'] ?? null;
                $payment->reference = $data['reference'] ?? null;
                $payment->paid_at = now();
                $payment->created_by = $actor->id;
                $payment->save();

                $this->ledger->credit($locked->id, $amount, LedgerType::Payment, $actor, payment: $payment);

                Customer::query()->whereKey($locked->id)->update([
                    'total_paid' => Dec::money(Dec::of($locked->total_paid)->plus($amount)),
                ]);

                return [$payment, true];
            });
        } catch (UniqueConstraintViolationException $e) {
            // Two identical requests raced; the unique index let one through.
            if ($existing = Payment::query()->where('client_uuid', $data['client_uuid'])->first()) {
                return [$existing, false];
            }

            throw $e;
        }
    }
}
