<?php

namespace App\Enums;

enum BillingCycle: string
{
    case Monthly = 'monthly';
    case Yearly = 'yearly';
    /** No renewal date. Used for the free plan. */
    case Lifetime = 'lifetime';
}
