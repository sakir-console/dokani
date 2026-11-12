<?php

namespace App\Enums;

enum StockMovementType: string
{
    case Opening = 'opening';
    case StockIn = 'stock_in';
    case StockOut = 'stock_out';
    case Adjustment = 'adjustment';
    case Sale = 'sale';
    case SaleVoid = 'sale_void';
    case Purchase = 'purchase';
}
