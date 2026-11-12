<?php

namespace App\Services\Reports;

use App\Exceptions\ApiException;
use App\Models\Shop;
use Illuminate\Support\Carbon;

/**
 * A reporting period, as whole calendar days in the shop's own time zone.
 *
 * "Today" for a shop in Dhaka starts at midnight in Dhaka, not midnight UTC.
 * $from and $to are the UTC instants that bound the period for queries.
 */
final class ReportRange
{
    public const KEYS = ['today', 'yesterday', 'last_7_days', 'this_week', 'this_month', 'custom'];

    public const MAX_DAYS = 366;

    private function __construct(
        public readonly string $key,
        public readonly Carbon $from,
        public readonly Carbon $to,
        public readonly string $timezone,
    ) {}

    /** @param array{range?: ?string, from?: ?string, to?: ?string} $input */
    public static function resolve(array $input, Shop $shop): self
    {
        $key = $input['range'] ?? 'today';
        $timezone = $shop->timezone;
        $now = now($timezone);

        [$start, $end] = match ($key) {
            'today' => [$now->copy(), $now->copy()],
            'yesterday' => [$now->copy()->subDay(), $now->copy()->subDay()],
            // Seven days including today.
            'last_7_days' => [$now->copy()->subDays(6), $now->copy()],
            'this_week' => [$now->copy()->startOfWeek(config('dokani.week_starts_on')), $now->copy()],
            'this_month' => [$now->copy()->startOfMonth(), $now->copy()],
            'custom' => self::custom($input, $timezone),
            default => throw self::invalid('range', __('Choose a valid date range.')),
        };

        return new self($key, $start->copy()->startOfDay()->utc(), $end->copy()->endOfDay()->utc(), $timezone);
    }

    /** @return array{0: Carbon, 1: Carbon} */
    private static function custom(array $input, string $timezone): array
    {
        if (empty($input['from']) || empty($input['to'])) {
            throw self::invalid('from', __('Choose a start and an end date.'));
        }

        $from = Carbon::parse($input['from'], $timezone);
        $to = Carbon::parse($input['to'], $timezone);

        if ($from->gt($to)) {
            throw self::invalid('to', __('The end date must not be before the start date.'));
        }
        if ($from->diffInDays($to) >= self::MAX_DAYS) {
            throw self::invalid('to', __('Choose a period of at most one year.'));
        }

        return [$from, $to];
    }

    private static function invalid(string $field, string $message): ApiException
    {
        return new ApiException('VALIDATION_FAILED', $message, 422, [$field => [$message]]);
    }

    public function fromLocal(): Carbon
    {
        return $this->from->copy()->timezone($this->timezone);
    }

    public function toLocal(): Carbon
    {
        return $this->to->copy()->timezone($this->timezone);
    }

    /** "12 Nov 2026" or "1 Nov 2026 – 12 Nov 2026". */
    public function label(): string
    {
        $from = $this->fromLocal()->format('j M Y');
        $to = $this->toLocal()->format('j M Y');

        return $from === $to ? $from : "{$from} – {$to}";
    }

    /** @return array{key: string, from: string, to: string, label: string} */
    public function toArray(): array
    {
        return [
            'key' => $this->key,
            'from' => $this->fromLocal()->toDateString(),
            'to' => $this->toLocal()->toDateString(),
            'label' => $this->label(),
        ];
    }
}
