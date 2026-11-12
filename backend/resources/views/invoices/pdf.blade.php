@php
    $money = fn ($amount) => rtrim(rtrim(number_format((float) $amount, 2), '0'), '.');
    $base = $receipt ? ($narrow ? 7.5 : 8.5) : 10.5;
@endphp
<html>
<head>
<style>
    body { font-family: hindsiliguri; font-size: {{ $base }}pt; color: #111; }
    h1 { font-size: {{ $base + ($receipt ? 3 : 7) }}pt; margin: 0; }
    .center { text-align: center; }
    .muted { color: #555; }
    .right { text-align: right; }
    table { width: 100%; border-collapse: collapse; }
    .items th { border-bottom: 0.3mm solid #111; text-align: left; padding: 1mm 0; font-weight: bold; }
    .items th.right { text-align: right; }
    .items td { padding: 1mm 0; border-bottom: 0.1mm solid #ccc; vertical-align: top; }
    .totals td { padding: 0.6mm 0; }
    .grand td { font-size: {{ $base + 2 }}pt; font-weight: bold; border-top: 0.3mm solid #111; padding-top: 1.2mm; }
    .rule { border-top: 0.2mm dashed #555; margin: 2mm 0; }
    .void { border: 0.4mm solid #b00; color: #b00; padding: 1mm; text-align: center; font-weight: bold; margin-bottom: 2mm; }
</style>
</head>
<body>
    @if ($invoice['status'] === 'voided')
        <div class="void">CANCELLED</div>
    @endif

    <div class="{{ $receipt ? 'center' : '' }}">
        <h1>{{ $invoice['shop']['name'] }}</h1>
        @if ($invoice['shop']['address'])<div class="muted">{{ $invoice['shop']['address'] }}</div>@endif
        @if ($invoice['shop']['phone'])<div class="muted">{{ $invoice['shop']['phone'] }}</div>@endif
    </div>

    <div class="rule"></div>

    <table>
        <tr>
            <td>Invoice: <b>{{ $invoice['invoice_no'] }}</b></td>
            <td class="right">{{ $invoice['sold_at']->format($receipt ? 'd/m/Y H:i' : 'j M Y, g:i A') }}</td>
        </tr>
        @if ($invoice['customer'])
            <tr><td colspan="2">Customer: {{ $invoice['customer']['name'] }} ({{ $invoice['customer']['phone_masked'] }})</td></tr>
        @endif
    </table>

    <div class="rule"></div>

    <table class="items">
        <thead>
            <tr>
                <th>Item</th>
                <th class="right">Qty</th>
                @unless ($narrow)<th class="right">Price</th>@endunless
                <th class="right">Amount</th>
            </tr>
        </thead>
        <tbody>
            @foreach ($invoice['items'] as $item)
                <tr>
                    <td>
                        {{ $item['name'] }}
                        @if ($narrow)<br><span class="muted">@ {{ $money($item['unit_price']) }}</span>@endif
                        @if ((float) $item['discount_amount'] > 0)<br><span class="muted">Discount -{{ $money($item['discount_amount']) }}</span>@endif
                    </td>
                    <td class="right">{{ $item['quantity'] }}</td>
                    @unless ($narrow)<td class="right">{{ $money($item['unit_price']) }}</td>@endunless
                    <td class="right">{{ $money($item['line_total']) }}</td>
                </tr>
            @endforeach
        </tbody>
    </table>

    <table class="totals" style="margin-top: 2mm;">
        <tr><td>Subtotal</td><td class="right">{{ $money($invoice['subtotal']) }}</td></tr>
        @if ((float) $invoice['discount_amount'] > 0)
            <tr><td>Discount</td><td class="right">-{{ $money($invoice['discount_amount']) }}</td></tr>
        @endif
        @if ((float) $invoice['additional_charge'] > 0)
            <tr><td>Additional charge</td><td class="right">{{ $money($invoice['additional_charge']) }}</td></tr>
        @endif
        <tr class="grand"><td>Total (BDT)</td><td class="right">{{ $money($invoice['grand_total']) }}</td></tr>
        @foreach ($invoice['payments'] as $payment)
            <tr><td>Paid ({{ $payment['label'] }})</td><td class="right">{{ $money($payment['amount']) }}</td></tr>
        @endforeach
        @if ((float) $invoice['change_amount'] > 0)
            <tr><td>Change returned</td><td class="right">{{ $money($invoice['change_amount']) }}</td></tr>
        @endif
        @if ((float) $invoice['due_amount'] > 0)
            <tr><td><b>Due</b></td><td class="right"><b>{{ $money($invoice['due_amount']) }}</b></td></tr>
        @endif
    </table>

    <div class="rule"></div>

    <div class="center">
        @if (class_exists(\Mpdf\QrCode\QrCode::class))
            <barcode code="{{ $invoice['url'] }}" type="QR" size="{{ $receipt ? '0.7' : '0.9' }}" error="M" disableborder="1" />
            <div class="muted">Scan to view this invoice</div>
        @else
            <div class="muted">{{ $invoice['url'] }}</div>
        @endif
        <div style="margin-top: 1.5mm;">{{ $invoice['shop']['footer'] ?: 'Thank you for shopping with us.' }}</div>
    </div>
</body>
</html>
