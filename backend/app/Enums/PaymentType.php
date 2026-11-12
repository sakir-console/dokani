<?php

namespace App\Enums;

enum PaymentType: string
{
    /** Paid at the counter as part of a sale. */
    case Sale = 'sale';

    /** A customer paying off an earlier due. */
    case DueCollection = 'due_collection';

    /** Money handed back when a sale is voided. */
    case Refund = 'refund';
}
