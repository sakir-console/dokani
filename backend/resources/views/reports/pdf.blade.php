<html>
<head>
<style>
    body { font-family: hindsiliguri; font-size: 9.5pt; color: #111; }
    h1 { font-size: 15pt; margin: 0; }
    .muted { color: #555; }
    table { width: 100%; border-collapse: collapse; margin-top: 4mm; }
    th { text-align: left; border-bottom: 0.3mm solid #111; padding: 1.5mm 1mm; font-weight: bold; }
    td { padding: 1.3mm 1mm; border-bottom: 0.1mm solid #ccc; vertical-align: top; }
    th.num, td.num { text-align: right; }
</style>
</head>
<body>
    <h1>{{ $table->title }}</h1>
    <div class="muted">{{ $table->shopName }}@if ($table->period) · {{ $table->period }}@endif</div>
    <div class="muted">Generated {{ now('Asia/Dhaka')->format('j M Y, g:i A') }}</div>

    <table>
        <thead>
            <tr>
                @foreach ($table->headings as $index => $heading)
                    <th class="{{ in_array($index, $table->numericColumns, true) ? 'num' : '' }}">{{ $heading }}</th>
                @endforeach
            </tr>
        </thead>
        <tbody>
            @forelse ($table->rows as $row)
                <tr>
                    @foreach ($row as $index => $cell)
                        <td class="{{ in_array($index, $table->numericColumns, true) ? 'num' : '' }}">{{ $cell }}</td>
                    @endforeach
                </tr>
            @empty
                <tr><td colspan="{{ count($table->headings) }}" class="muted">Nothing to show for this period.</td></tr>
            @endforelse
        </tbody>
    </table>
</body>
</html>
