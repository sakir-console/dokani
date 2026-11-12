<?php

namespace App\Services\Customers;

use App\Enums\LedgerType;
use App\Models\Customer;
use App\Models\CustomerLedger;
use App\Models\Payment;
use App\Models\Sale;
use App\Models\User;
use App\Support\Dec;
use Brick\Math\BigDecimal;
use Illuminate\Support\Facades\DB;

/**
 * The only place a customer's balance changes.
 *
 * Each change locks the customer row, appends a ledger entry carrying the
 * new running balance, and updates the cached current_due — in one
 * transaction, so the cache can never drift from the ledger.
 */
class LedgerService
{
    /** The customer owes more (a sale on credit, an opening balance). */
    public function debit(int $customerId, BigDecimal|string $amount, LedgerType $type, ?User $actor = null, ?Sale $sale = null, ?string $note = null): CustomerLedger
    {
        return $this->record($customerId, Dec::of($amount), Dec::of(0), $type, $actor, $sale, null, $note);
    }

    /** The customer owes less (a payment, a voided sale). */
    public function credit(int $customerId, BigDecimal|string $amount, LedgerType $type, ?User $actor = null, ?Sale $sale = null, ?Payment $payment = null, ?string $note = null): CustomerLedger
    {
        return $this->record($customerId, Dec::of(0), Dec::of($amount), $type, $actor, $sale, $payment, $note);
    }

    private function record(int $customerId, BigDecimal $debit, BigDecimal $credit, LedgerType $type, ?User $actor, ?Sale $sale, ?Payment $payment, ?string $note): CustomerLedger
    {
        return DB::transaction(function () use ($customerId, $debit, $credit, $type, $actor, $sale, $payment, $note) {
            $customer = Customer::query()->withTrashed()->lockForUpdate()->findOrFail($customerId);

            $balance = Dec::of($customer->current_due)->plus($debit)->minus($credit);

            $customer->current_due = Dec::money($balance);
            $customer->save();

            $entry = new CustomerLedger;
            $entry->customer_id = $customer->id;
            $entry->type = $type;
            $entry->debit = Dec::money($debit);
            $entry->credit = Dec::money($credit);
            $entry->balance_after = Dec::money($balance);
            $entry->sale_id = $sale?->id;
            $entry->payment_id = $payment?->id;
            $entry->note = $note;
            $entry->created_by = $actor?->id;
            $entry->save();

            return $entry;
        });
    }
}
