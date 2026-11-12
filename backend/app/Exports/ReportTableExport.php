<?php

namespace App\Exports;

use App\Services\Reports\ReportTable;
use Maatwebsite\Excel\Concerns\FromArray;
use Maatwebsite\Excel\Concerns\ShouldAutoSize;
use Maatwebsite\Excel\Concerns\WithCustomValueBinder;
use Maatwebsite\Excel\Concerns\WithHeadings;
use Maatwebsite\Excel\Concerns\WithStrictNullComparison;
use Maatwebsite\Excel\Concerns\WithStyles;
use Maatwebsite\Excel\Concerns\WithTitle;
use PhpOffice\PhpSpreadsheet\Cell\Cell;
use PhpOffice\PhpSpreadsheet\Cell\DataType;
use PhpOffice\PhpSpreadsheet\Cell\DefaultValueBinder;
use PhpOffice\PhpSpreadsheet\Worksheet\Worksheet;

/**
 * Writes a ReportTable as an Excel workbook.
 */
class ReportTableExport extends DefaultValueBinder implements FromArray, ShouldAutoSize, WithCustomValueBinder, WithHeadings, WithStrictNullComparison, WithStyles, WithTitle
{
    public function __construct(private readonly ReportTable $table) {}

    public function array(): array
    {
        return $this->table->rows;
    }

    public function headings(): array
    {
        return $this->table->headings;
    }

    public function title(): string
    {
        // Sheet names: at most 31 characters, and none of : \ / ? * [ ]
        return mb_substr(preg_replace('/[:\\\\\/?*\[\]]/', ' ', $this->table->title), 0, 31);
    }

    public function styles(Worksheet $sheet): ?array
    {
        return [1 => ['font' => ['bold' => true]]];
    }

    /**
     * Amounts become real numbers a shopkeeper can sum. Phone numbers, barcodes
     * and invoice numbers stay text: as numbers they would lose leading zeros
     * or turn into 8.9E+12.
     */
    public function bindValue(Cell $cell, mixed $value): bool
    {
        if (is_string($value) && $this->mustStayText($value)) {
            $cell->setValueExplicit($value, DataType::TYPE_STRING);

            return true;
        }

        return parent::bindValue($cell, $value);
    }

    private function mustStayText(string $value): bool
    {
        // 01712345678, 0001234: leading zeros matter.
        if (preg_match('/^0\d+$/', $value) === 1) {
            return true;
        }
        // 8941100000017: too long to be an amount; Excel would show 8.94E+12.
        if (preg_match('/^\d{12,}$/', $value) === 1) {
            return true;
        }

        // Text starting with = + - @ would be run as a formula by a spreadsheet
        // (a product or customer named "=cmd|..."). Real negative amounts are still numbers.
        return preg_match('/^[=+\-@]/', $value) === 1 && preg_match('/^-?\d+(\.\d+)?$/', $value) !== 1;
    }
}
