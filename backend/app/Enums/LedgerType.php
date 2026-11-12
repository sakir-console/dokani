<?php

namespace App\Enums;

enum LedgerType: string
{
    case Opening = 'opening';
    case SaleDue = 'sale_due';
    case Payment = 'payment';
    case SaleVoid = 'sale_void';
    case Adjustment = 'adjustment';
}
