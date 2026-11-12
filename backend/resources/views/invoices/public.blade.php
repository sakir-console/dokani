@php
    $money = fn ($amount) => '৳'.rtrim(rtrim(number_format((float) $amount, 2), '0'), '.');
    $voided = $invoice['status'] === 'voided';
@endphp
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>{{ $invoice['invoice_no'] }} · {{ $invoice['shop']['name'] }}</title>
    <style>
        *, *::before, *::after { box-sizing: border-box; }
        body { margin: 0; background: #f1f5f9; color: #0f172a; font: 16px/1.5 system-ui, 'Segoe UI', 'Noto Sans', 'Noto Sans Bengali', sans-serif; }
        main { max-width: 34rem; margin: 0 auto; padding: 1rem; }
        .card { background: #fff; border: 1px solid #e2e8f0; border-radius: 1rem; padding: 1.25rem; }
        h1 { font-size: 1.35rem; margin: 0; line-height: 1.3; }
        .muted { color: #64748b; font-size: .9rem; }
        .head { display: flex; gap: .9rem; align-items: center; }
        .head img { width: 3.5rem; height: 3.5rem; border-radius: .75rem; object-fit: cover; border: 1px solid #e2e8f0; }
        .meta { display: flex; justify-content: space-between; gap: 1rem; flex-wrap: wrap; margin: 1rem 0; padding: .75rem 0; border-block: 1px solid #e2e8f0; }
        .meta strong { display: block; }
        table { width: 100%; border-collapse: collapse; }
        th { text-align: left; font-size: .8rem; font-weight: 600; color: #64748b; padding: .4rem 0; border-bottom: 1px solid #e2e8f0; }
        td { padding: .55rem 0; vertical-align: top; border-bottom: 1px solid #f1f5f9; }
        .num { text-align: right; white-space: nowrap; font-variant-numeric: tabular-nums; }
        .totals { margin-top: .75rem; }
        .totals div { display: flex; justify-content: space-between; padding: .2rem 0; }
        .totals .grand { font-size: 1.2rem; font-weight: 700; border-top: 1px solid #e2e8f0; margin-top: .4rem; padding-top: .6rem; }
        .due { color: #b91c1c; font-weight: 600; }
        .paid { color: #047857; }
        .banner { background: #fef2f2; color: #b91c1c; border: 1px solid #fecaca; border-radius: .75rem; padding: .6rem .9rem; margin-bottom: 1rem; font-weight: 600; }
        .actions { margin-top: 1rem; display: flex; gap: .5rem; }
        .button { flex: 1; text-align: center; padding: .7rem 1rem; border-radius: .75rem; background: #059669; color: #fff; text-decoration: none; font-weight: 600; }
        .button:focus-visible { outline: 3px solid #065f46; outline-offset: 2px; }
        footer { text-align: center; margin: 1rem 0; }
        @media print { body { background: #fff; } .card { border: 0; padding: 0; } .actions { display: none; } }
    </style>
</head>
<body>
<main>
    <div class="card">
        @if ($voided)
            <p class="banner" role="status">This sale was cancelled.</p>
        @endif

        <div class="head">
            @if ($invoice['shop']['logo_url'])
                <img src="{{ $invoice['shop']['logo_url'] }}" alt="">
            @endif
            <div>
                <h1>{{ $invoice['shop']['name'] }}</h1>
                <div class="muted">
                    {{ collect([$invoice['shop']['address'], $invoice['shop']['phone']])->filter()->join(' · ') }}
                </div>
            </div>
        </div>

        <div class="meta">
            <div><span class="muted">Invoice</span><strong>{{ $invoice['invoice_no'] }}</strong></div>
            <div><span class="muted">Date</span><strong>{{ $invoice['sold_at']->format('j M Y, g:i A') }}</strong></div>
            @if ($invoice['customer'])
                <div><span class="muted">Customer</span><strong>{{ $invoice['customer']['name'] }}</strong><span class="muted">{{ $invoice['customer']['phone_masked'] }}</span></div>
            @endif
        </div>

        <table>
            <thead>
                <tr><th scope="col">Item</th><th scope="col" class="num">Qty × Price</th><th scope="col" class="num">Amount</th></tr>
            </thead>
            <tbody>
                @foreach ($invoice['items'] as $item)
                    <tr>
                        <td>
                            {{ $item['name'] }}
                            @if ((float) $item['discount_amount'] > 0)
                                <div class="muted">Discount −{{ $money($item['discount_amount']) }}</div>
                            @endif
                        </td>
                        <td class="num">{{ $item['quantity'] }} × {{ $money($item['unit_price']) }}</td>
                        <td class="num">{{ $money($item['line_total']) }}</td>
                    </tr>
                @endforeach
            </tbody>
        </table>

        <div class="totals">
            <div><span>Subtotal</span><span class="num">{{ $money($invoice['subtotal']) }}</span></div>
            @if ((float) $invoice['discount_amount'] > 0)
                <div><span>Discount</span><span class="num">−{{ $money($invoice['discount_amount']) }}</span></div>
            @endif
            @if ((float) $invoice['additional_charge'] > 0)
                <div><span>Additional charge</span><span class="num">{{ $money($invoice['additional_charge']) }}</span></div>
            @endif
            <div class="grand"><span>Total</span><span class="num">{{ $money($invoice['grand_total']) }}</span></div>
            @foreach ($invoice['payments'] as $payment)
                <div class="paid"><span>Paid · {{ $payment['label'] }}</span><span class="num">{{ $money($payment['amount']) }}</span></div>
            @endforeach
            @if ((float) $invoice['change_amount'] > 0)
                <div class="muted"><span>Change returned</span><span class="num">{{ $money($invoice['change_amount']) }}</span></div>
            @endif
            @if ((float) $invoice['due_amount'] > 0)
                <div class="due"><span>Due</span><span class="num">{{ $money($invoice['due_amount']) }}</span></div>
            @endif
        </div>

        <div class="actions">
            <a class="button" href="{{ url('/i/'.$token.'/pdf') }}">Download PDF</a>
        </div>
    </div>

    <footer class="muted">
        {{ $invoice['shop']['footer'] ?: 'Thank you for shopping with us.' }}
    </footer>
</main>
</body>
</html>
