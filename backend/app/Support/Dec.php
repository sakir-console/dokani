<?php

namespace App\Support;

use Brick\Math\BigDecimal;
use Brick\Math\RoundingMode;

/**
 * Exact decimal arithmetic for money and quantities. PHP floats are never
 * used for either: 0.1 + 0.2 is not 0.3 in floating point.
 */
final class Dec
{
    public static function of(BigDecimal|string|int|float|null $value): BigDecimal
    {
        if ($value instanceof BigDecimal) {
            return $value;
        }

        // Floats are converted through their shortest string form, never used in arithmetic.
        return BigDecimal::of($value === null || $value === '' ? '0' : (string) $value);
    }

    /** Money: two decimal places, half-up. */
    public static function money(BigDecimal|string|int|float|null $value): string
    {
        return (string) self::of($value)->toScale(2, RoundingMode::HalfUp);
    }

    /** Quantity: three decimal places, half-up. */
    public static function qty(BigDecimal|string|int|float|null $value): string
    {
        return (string) self::of($value)->toScale(3, RoundingMode::HalfUp);
    }

    public static function isWhole(BigDecimal|string|int|float|null $value): bool
    {
        return self::of($value)->strippedOfTrailingZeros()->getScale() <= 0;
    }
}
