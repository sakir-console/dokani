<?php

namespace App\Services\Reports;

/**
 * A report as a plain table: what every export format is written from.
 */
final class ReportTable
{
    /**
     * @param  list<string>  $headings
     * @param  list<list<string|int|null>>  $rows
     * @param  list<int>  $numericColumns  zero-based indexes of columns holding amounts or quantities (right-aligned in PDF)
     */
    public function __construct(
        public readonly string $slug,
        public readonly string $title,
        public readonly string $shopName,
        public readonly ?string $period,
        public readonly array $headings,
        public readonly array $rows,
        public readonly array $numericColumns = [],
    ) {}

    public function fileName(string $extension): string
    {
        return $this->slug.'-'.now()->format('Ymd-His').'.'.$extension;
    }
}
