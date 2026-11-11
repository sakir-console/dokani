@php
    $limit = fn ($value) => $value === null ? 'Unlimited' : number_format($value);
@endphp
<div>
    <a href="{{ route('admin.shops.index') }}" wire:navigate class="text-sm font-medium text-slate-500 hover:text-slate-900">← Shops</a>

    <header class="mt-3 flex flex-wrap items-start justify-between gap-4">
        <div class="flex items-center gap-4">
            @if ($shop->logoUrl())
                <img src="{{ $shop->logoUrl() }}" alt="" class="h-14 w-14 rounded-xl border border-slate-200 object-cover">
            @else
                <span class="flex h-14 w-14 items-center justify-center rounded-xl bg-slate-200 text-xl font-semibold text-slate-600">{{ mb_substr($shop->name, 0, 1) }}</span>
            @endif
            <div>
                <h1 class="text-2xl font-semibold">{{ $shop->name }}</h1>
                <p class="mt-1 flex flex-wrap items-center gap-2 text-sm text-slate-500">
                    <x-admin.status-badge :status="$shop->status" />
                    <span>{{ $shop->shop_type->label() }}</span>
                    <span>· Registered {{ $shop->created_at->format('j M Y') }}</span>
                </p>
            </div>
        </div>

        <div class="flex flex-wrap gap-2">
            @if ($shop->status !== \App\Enums\ShopStatus::Active)
                <button type="button" wire:click="activate" wire:loading.attr="disabled"
                        class="rounded-lg bg-brand-600 px-3.5 py-2 text-sm font-semibold text-white hover:bg-brand-700 disabled:opacity-60">
                    {{ $shop->status === \App\Enums\ShopStatus::Suspended ? 'Restore shop' : 'Activate' }}
                </button>
            @endif
            @if ($shop->status === \App\Enums\ShopStatus::Active)
                <button type="button" wire:click="deactivate" wire:confirm="Deactivate this shop? Its users will not be able to use the app until it is activated again."
                        class="rounded-lg border border-slate-300 bg-white px-3.5 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-50">
                    Deactivate
                </button>
            @endif
            @if ($shop->status !== \App\Enums\ShopStatus::Suspended)
                <button type="button" wire:click="$set('confirmingSuspend', true)"
                        class="rounded-lg border border-red-200 bg-white px-3.5 py-2 text-sm font-semibold text-red-700 hover:bg-red-50">
                    Suspend
                </button>
            @endif
        </div>
    </header>

    @if (session('status'))
        <p class="mt-4 rounded-lg border border-brand-100 bg-brand-50 px-4 py-2.5 text-sm text-brand-900" role="status">{{ session('status') }}</p>
    @endif

    @if ($shop->status === \App\Enums\ShopStatus::Suspended && $shop->suspended_reason)
        <p class="mt-4 rounded-lg border border-red-200 bg-red-50 px-4 py-2.5 text-sm text-red-800"><span class="font-medium">Suspension reason:</span> {{ $shop->suspended_reason }}</p>
    @endif

    @if ($confirmingSuspend)
        <form wire:submit="suspend" class="mt-4 rounded-xl border border-red-200 bg-white p-5">
            <h2 class="text-base font-semibold">Suspend {{ $shop->name }}?</h2>
            <p class="mt-1 text-sm text-slate-600">The shop's users are blocked from the app immediately. No data is deleted, and you can restore the shop at any time.</p>
            <label for="reason" class="mt-4 block text-sm font-medium text-slate-700">Reason (kept in the audit log)</label>
            <input id="reason" type="text" wire:model="reason" maxlength="255"
                   class="mt-1 block w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20">
            @error('reason') <p class="mt-1 text-sm text-red-600" role="alert">{{ $message }}</p> @enderror
            <div class="mt-4 flex gap-2">
                <button type="submit" class="rounded-lg bg-red-600 px-3.5 py-2 text-sm font-semibold text-white hover:bg-red-700">Suspend shop</button>
                <button type="button" wire:click="$set('confirmingSuspend', false)" class="rounded-lg px-3.5 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100">Cancel</button>
            </div>
        </form>
    @endif

    <div class="mt-6 grid gap-6 lg:grid-cols-2">
        <section class="rounded-xl border border-slate-200 bg-white p-5" aria-labelledby="details-heading">
            <h2 id="details-heading" class="text-base font-semibold">Shop details</h2>
            <dl class="mt-3 divide-y divide-slate-100 text-sm">
                <div class="flex justify-between gap-4 py-2"><dt class="text-slate-500">Owner</dt><dd class="text-right font-medium">{{ $shop->owner?->name }}</dd></div>
                <div class="flex justify-between gap-4 py-2"><dt class="text-slate-500">Owner phone</dt><dd class="text-right tabular-nums">{{ $shop->owner?->phone }}</dd></div>
                <div class="flex justify-between gap-4 py-2"><dt class="text-slate-500">Shop phone</dt><dd class="text-right tabular-nums">{{ $shop->phone }}</dd></div>
                <div class="flex justify-between gap-4 py-2"><dt class="text-slate-500">Address</dt><dd class="text-right">{{ $shop->address ?: '—' }}</dd></div>
                <div class="flex justify-between gap-4 py-2"><dt class="text-slate-500">Last owner login</dt><dd class="text-right">{{ $shop->owner?->last_login_at?->diffForHumans() ?? 'Never' }}</dd></div>
                <div class="flex justify-between gap-4 py-2"><dt class="text-slate-500">Staff accounts</dt><dd class="text-right tabular-nums">{{ $shop->memberships->count() }}</dd></div>
            </dl>
        </section>

        <section class="rounded-xl border border-slate-200 bg-white p-5" aria-labelledby="plan-heading">
            <h2 id="plan-heading" class="text-base font-semibold">Subscription</h2>
            <dl class="mt-3 divide-y divide-slate-100 text-sm">
                <div class="flex justify-between gap-4 py-2"><dt class="text-slate-500">Plan</dt><dd class="text-right font-medium">{{ $plan->name }}@if (! $subscription) <span class="font-normal text-slate-500">(fallback)</span>@endif</dd></div>
                <div class="flex justify-between gap-4 py-2"><dt class="text-slate-500">Billing</dt><dd class="text-right">{{ $subscription ? ucfirst($subscription->billing_cycle->value) : '—' }}</dd></div>
                <div class="flex justify-between gap-4 py-2"><dt class="text-slate-500">Renews / expires</dt><dd class="text-right">{{ $subscription?->ends_at?->format('j M Y') ?? 'No expiry' }}</dd></div>
                <div class="flex justify-between gap-4 py-2"><dt class="text-slate-500">Product limit</dt><dd class="text-right tabular-nums">{{ $limit($limits['max_products']) }}</dd></div>
                <div class="flex justify-between gap-4 py-2"><dt class="text-slate-500">Staff limit</dt><dd class="text-right tabular-nums">{{ $limit($limits['max_users']) }}</dd></div>
                <div class="flex justify-between gap-4 py-2"><dt class="text-slate-500">Monthly sales limit</dt><dd class="text-right tabular-nums">{{ $limit($limits['max_monthly_sales']) }}</dd></div>
            </dl>
            <h3 class="mt-4 text-sm font-medium text-slate-700">Enabled modules</h3>
            <ul class="mt-2 flex flex-wrap gap-1.5">
                @foreach ($modules as $module)
                    <li class="rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-700">{{ $module }}</li>
                @endforeach
            </ul>
        </section>
    </div>

    <section class="mt-6 rounded-xl border border-slate-200 bg-white" aria-labelledby="shop-activity-heading">
        <div class="border-b border-slate-200 px-5 py-3">
            <h2 id="shop-activity-heading" class="text-base font-semibold">Activity</h2>
        </div>
        <ul class="divide-y divide-slate-100">
            @forelse ($activity as $entry)
                <li class="flex items-center justify-between gap-4 px-5 py-3 text-sm">
                    <span><span class="font-medium">{{ $entry->action }}</span> <span class="text-slate-500">by {{ $entry->actor_type }}</span></span>
                    <span class="whitespace-nowrap text-xs text-slate-500">{{ $entry->created_at->timezone('Asia/Dhaka')->format('j M Y, g:i A') }}</span>
                </li>
            @empty
                <li class="px-5 py-8 text-center text-sm text-slate-500">No recorded activity for this shop.</li>
            @endforelse
        </ul>
    </section>
</div>
