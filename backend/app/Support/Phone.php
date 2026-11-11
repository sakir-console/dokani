<?php

namespace App\Support;

/**
 * Bangladeshi mobile numbers.
 *
 * Accepts 01712345678, +8801712345678, 8801712345678, with spaces or dashes,
 * and Bengali digits (০১৭…). The stored form is always 01XXXXXXXXX.
 */
final class Phone
{
    private const BENGALI_DIGITS = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

    public static function normalize(?string $input): ?string
    {
        if ($input === null) {
            return null;
        }

        $value = str_replace(self::BENGALI_DIGITS, range(0, 9), trim($input));
        $value = preg_replace('/[\s\-().]/', '', $value) ?? '';

        if (str_starts_with($value, '+')) {
            $value = substr($value, 1);
        }
        if (str_starts_with($value, '8801')) {
            $value = substr($value, 2);
        }

        return preg_match('/^01[3-9]\d{8}$/', $value) === 1 ? $value : null;
    }

    public static function isValid(?string $input): bool
    {
        return self::normalize($input) !== null;
    }

    /** 01712345678 → 017*****678, for anything shown publicly. */
    public static function mask(string $phone): string
    {
        return substr($phone, 0, 3).str_repeat('*', max(strlen($phone) - 6, 0)).substr($phone, -3);
    }
}
