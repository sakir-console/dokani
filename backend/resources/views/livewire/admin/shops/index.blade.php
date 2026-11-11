<div>
    <header class="mb-6">
        <h1 class="text-2xl font-semibold">Shops</h1>
        <p class="mt-1 text-sm text-slate-500">{{ number_format($shops->total()) }} {{ Str::plural('shop', $shops->total()) }} match</p>
    </header>

    <div class="mb-4 grid gap-3 sm:grid-cols-[1fr_auto_auto_auto]">
        <div>
            <label for="search" class="sr-only">Search shops</label>
            <input id="search" type="search" wire:model.live.debounce.300ms="search" placeholder="Search by shop, owner or phone"
                   class="block w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20">
        </div>
        <div>
            <label for="status" class="sr-only">Status</label>
            <select id="status" wire:model.live="status" class="block w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm">
                <option value="">All statuses</option>
                @foreach ($statuses as $option)
                    <option value="{{ $option->value }}">{{ $option->label() }}</option>
                @endforeach
            </select>
        </div>
        <div>
            <label for="type" class="sr-only">Shop type</label>
            <select id="type" wire:model.live="type" class="block w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm">
                <option value="">All types</option>
                @foreach ($types as $option)
                    <option value="{{ $option->value }}">{{ $option->label() }}</option>
                @endforeach
            </select>
        </div>
        @if ($search !== '' || $status !== '' || $type !== '')
            <button type="button" wire:click="clearFilters" class="rounded-lg px-3 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100">Clear</button>
        @endif
    </div>

    <div class="overflow-hidden rounded-xl border border-slate-200 bg-white">
        <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-slate-200 text-sm">
                <thead class="bg-slate-50 text-left text-xs font-medium text-slate-500">
                    <tr>
                        <th scope="col" class="px-4 py-3">Shop</th>
                        <th scope="col" class="px-4 py-3">Owner</th>
                        <th scope="col" class="px-4 py-3">Type</th>
                        <th scope="col" class="px-4 py-3">Plan</th>
                        <th scope="col" class="px-4 py-3">Status</th>
                        <th scope="col" class="px-4 py-3">Registered</th>
                    </tr>
                </thead>
                <tbody class="divide-y divide-slate-100">
                    @forelse ($shops as $shop)
                        <tr wire:key="shop-{{ $shop->id }}" class="hover:bg-slate-50">
                            <td class="px-4 py-3">
                                <a href="{{ route('admin.shops.show', $shop->id) }}" wire:navigate class="font-medium text-slate-900 hover:text-brand-700 hover:underline">{{ $shop->name }}</a>
                                <div class="text-xs text-slate-500">{{ $shop->phone }}</div>
                            </td>
                            <td class="px-4 py-3">
                                {{ $shop->owner?->name }}
                                <div class="text-xs text-slate-500">{{ $shop->owner?->phone }}</div>
                            </td>
                            <td class="px-4 py-3 text-slate-600">{{ $shop->shop_type->label() }}</td>
                            <td class="px-4 py-3 text-slate-600">{{ $shop->activeSubscription?->plan?->name ?? 'Free (fallback)' }}</td>
                            <td class="px-4 py-3"><x-admin.status-badge :status="$shop->status" /></td>
                            <td class="whitespace-nowrap px-4 py-3 text-slate-600">{{ $shop->created_at->format('j M Y') }}</td>
                        </tr>
                    @empty
                        <tr>
                            <td colspan="6" class="px-4 py-12 text-center text-slate-500">
                                @if ($search !== '' || $status !== '' || $type !== '')
                                    No shops match these filters.
                                @else
                                    No shops have registered yet. They appear here as soon as an owner signs up in the app.
                                @endif
                            </td>
                        </tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <div class="mt-4">{{ $shops->links() }}</div>
</div>
