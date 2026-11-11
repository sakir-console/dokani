@props(['status'])
@php
    $styles = [
        'active' => 'bg-brand-50 text-brand-700 ring-brand-600/20',
        'inactive' => 'bg-slate-100 text-slate-700 ring-slate-500/20',
        'suspended' => 'bg-red-50 text-red-700 ring-red-600/20',
    ];
@endphp
<span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset {{ $styles[$status->value] ?? $styles['inactive'] }}">
    {{ $status->label() }}
</span>
