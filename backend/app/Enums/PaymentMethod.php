<?php

namespace App\Enums;

enum PaymentMethod: string
{
    case Cash = 'cash';
    case Bkash = 'bkash';
    case Nagad = 'nagad';
    case Bank = 'bank';
    case Card = 'card';
    case Other = 'other';

    public function label(): string
    {
        return match ($this) {
            self::Cash => 'Cash',
            self::Bkash => 'bKash',
            self::Nagad => 'Nagad',
            self::Bank => 'Bank',
            self::Card => 'Card',
            self::Other => 'Other',
        };
    }

    public function labelBn(): string
    {
        return match ($this) {
            self::Cash => 'নগদ',
            self::Bkash => 'বিকাশ',
            self::Nagad => 'নগদ (Nagad)',
            self::Bank => 'ব্যাংক',
            self::Card => 'কার্ড',
            self::Other => 'অন্যান্য',
        };
    }
}
