@props(['label', 'value', 'hint' => null, 'tone' => 'slate'])
@php
    $tones = [
        'slate' => 'text-slate-900',
        'green' => 'text-brand-700',
        'amber' => 'text-amber-700',
        'red' => 'text-red-700',
    ];
@endphp
<div {{ $attributes->class('rounded-xl border border-slate-200 bg-white p-4') }}>
    <p class="text-sm text-slate-500">{{ $label }}</p>
    <p class="mt-1 text-2xl font-semibold tabular-nums {{ $tones[$tone] ?? $tones['slate'] }}">{{ $value }}</p>
    @if ($hint)
        <p class="mt-1 text-xs text-slate-500">{{ $hint }}</p>
    @endif
</div>
