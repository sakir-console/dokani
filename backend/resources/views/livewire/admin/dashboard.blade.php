@php
    $money = fn (float $amount) => '৳'.number_format($amount, 0);
    $peak = max($series->max('total'), 1);
@endphp
<div>
    <header class="mb-6">
        <h1 class="text-2xl font-semibold">Dashboard</h1>
        <p class="mt-1 text-sm text-slate-500">Platform overview as of {{ now()->timezone('Asia/Dhaka')->format('j M Y, g:i A') }} (Dhaka)</p>
    </header>

    <section aria-labelledby="shops-heading">
        <h2 id="shops-heading" class="mb-3 text-sm font-medium text-slate-500">Shops</h2>
        <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <x-admin.stat label="Registered shops" :value="number_format($shops['total'])" />
            <x-admin.stat label="Active" :value="number_format($shops['active'])" tone="green" />
            <x-admin.stat label="Inactive" :value="number_format($shops['inactive'])" />
            <x-admin.stat label="Suspended" :value="number_format($shops['suspended'])" :tone="$shops['suspended'] ? 'red' : 'slate'" />
        </div>
    </section>

    <section class="mt-8" aria-labelledby="subs-heading">
        <h2 id="subs-heading" class="mb-3 text-sm font-medium text-slate-500">Subscriptions</h2>
        <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <x-admin.stat label="Monthly recurring revenue" :value="$money($subscriptions['mrr'])" hint="Paid subscriptions in force" tone="green" />
            <x-admin.stat label="Total subscription revenue" :value="$money($subscriptions['total_revenue'])" hint="All recorded payments" />
            <x-admin.stat label="Paid shops" :value="number_format($subscriptions['paid'])" />
            <x-admin.stat label="Free shops" :value="number_format($subscriptions['free'])" />
            <x-admin.stat label="Expiring within 7 days" :value="number_format($subscriptions['expiring_7_days'])" :tone="$subscriptions['expiring_7_days'] ? 'amber' : 'slate'" />
            <x-admin.stat label="Expired, not renewed" :value="number_format($subscriptions['expired'])" :tone="$subscriptions['expired'] ? 'red' : 'slate'" />
            <x-admin.stat label="Total users" :value="number_format($registrations['total_users'])" />
            <x-admin.stat label="New shops, last 30 days" :value="number_format($registrations['last_30_days'])" :hint="$registrations['today'].' today · '.$registrations['last_7_days'].' this week'" />
        </div>
    </section>

    <section class="mt-8 rounded-xl border border-slate-200 bg-white p-5" aria-labelledby="chart-heading">
        <h2 id="chart-heading" class="text-base font-semibold">New shop registrations</h2>
        <p class="text-sm text-slate-500">Last {{ $series->count() }} days · {{ $series->sum('total') }} total</p>

        <div class="mt-5 flex h-36 items-end gap-1.5" role="img" aria-label="Bar chart of new shop registrations per day">
            @foreach ($series as $day)
                <div class="group relative flex h-full flex-1 flex-col justify-end" title="{{ $day['label'] }}: {{ $day['total'] }}">
                    <span class="mb-1 text-center text-xs tabular-nums text-slate-500 {{ $day['total'] ? '' : 'invisible' }}">{{ $day['total'] }}</span>
                    <div class="w-full rounded-t {{ $day['total'] ? 'bg-brand-500' : 'bg-slate-200' }}"
                         style="height: {{ $day['total'] ? max(round($day['total'] / $peak * 100), 6) : 2 }}%"></div>
                </div>
            @endforeach
        </div>
        <div class="mt-2 flex justify-between text-xs text-slate-500">
            <span>{{ $series->first()['label'] }}</span>
            <span>{{ $series->last()['label'] }}</span>
        </div>
    </section>

    <div class="mt-8 grid gap-6 lg:grid-cols-2">
        <section class="rounded-xl border border-slate-200 bg-white" aria-labelledby="recent-shops-heading">
            <div class="flex items-center justify-between border-b border-slate-200 px-5 py-3">
                <h2 id="recent-shops-heading" class="text-base font-semibold">Newest shops</h2>
                <a href="{{ route('admin.shops.index') }}" wire:navigate class="text-sm font-medium text-brand-700 hover:underline">View all</a>
            </div>
            <ul class="divide-y divide-slate-100">
                @forelse ($recentShops as $shop)
                    <li>
                        <a href="{{ route('admin.shops.show', $shop->id) }}" wire:navigate class="flex items-center justify-between gap-3 px-5 py-3 hover:bg-slate-50">
                            <span class="min-w-0">
                                <span class="block truncate text-sm font-medium">{{ $shop->name }}</span>
                                <span class="block truncate text-xs text-slate-500">{{ $shop->owner?->name }} · {{ $shop->created_at->diffForHumans() }}</span>
                            </span>
                            <x-admin.status-badge :status="$shop->status" />
                        </a>
                    </li>
                @empty
                    <li class="px-5 py-8 text-center text-sm text-slate-500">No shops have registered yet.</li>
                @endforelse
            </ul>
        </section>

        <section class="rounded-xl border border-slate-200 bg-white" aria-labelledby="activity-heading">
            <div class="border-b border-slate-200 px-5 py-3">
                <h2 id="activity-heading" class="text-base font-semibold">Recent activity</h2>
            </div>
            <ul class="divide-y divide-slate-100">
                @forelse ($activity as $entry)
                    <li class="px-5 py-3">
                        <p class="text-sm"><span class="font-medium">{{ $entry->action }}</span>@if ($entry->shop) <span class="text-slate-500">· {{ $entry->shop->name }}</span>@endif</p>
                        <p class="text-xs text-slate-500">{{ ucfirst($entry->actor_type) }} · {{ $entry->created_at->diffForHumans() }}</p>
                    </li>
                @empty
                    <li class="px-5 py-8 text-center text-sm text-slate-500">Nothing has happened yet.</li>
                @endforelse
            </ul>
        </section>
    </div>
</div>
