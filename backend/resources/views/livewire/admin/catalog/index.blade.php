<div>
    <header class="mb-6 flex flex-wrap items-end justify-between gap-3">
        <div>
            <h1 class="text-2xl font-semibold">Global catalogue</h1>
            <p class="mt-1 text-sm text-slate-500">Products shops can import. They carry no price or stock; each shop sets its own.</p>
        </div>
        <a href="{{ route('admin.catalog.create') }}" wire:navigate
           class="rounded-lg bg-brand-600 px-3.5 py-2 text-sm font-semibold text-white hover:bg-brand-700">Add product</a>
    </header>

    @if (session('status'))
        <p class="mb-4 rounded-lg border border-brand-100 bg-brand-50 px-4 py-2.5 text-sm text-brand-900" role="status">{{ session('status') }}</p>
    @endif

    <div class="mb-4 grid gap-3 sm:grid-cols-[1fr_auto]">
        <div>
            <label for="search" class="sr-only">Search catalogue</label>
            <input id="search" type="search" wire:model.live.debounce.300ms="search" placeholder="Search by name, brand or barcode"
                   class="block w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20">
        </div>
        <div>
            <label for="category" class="sr-only">Category</label>
            <select id="category" wire:model.live="category" class="block w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm">
                <option value="">All categories</option>
                @foreach ($categories as $option)
                    <option value="{{ $option->id }}">{{ $option->name }}</option>
                @endforeach
            </select>
        </div>
    </div>

    <div class="overflow-hidden rounded-xl border border-slate-200 bg-white">
        <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-slate-200 text-sm">
                <thead class="bg-slate-50 text-left text-xs font-medium text-slate-500">
                    <tr>
                        <th scope="col" class="px-4 py-3">Product</th>
                        <th scope="col" class="px-4 py-3">Category</th>
                        <th scope="col" class="px-4 py-3">Unit</th>
                        <th scope="col" class="px-4 py-3">Variants</th>
                        <th scope="col" class="px-4 py-3">Visible to shops</th>
                        <th scope="col" class="px-4 py-3"><span class="sr-only">Actions</span></th>
                    </tr>
                </thead>
                <tbody class="divide-y divide-slate-100">
                    @forelse ($products as $product)
                        <tr wire:key="gp-{{ $product->id }}" class="hover:bg-slate-50">
                            <td class="px-4 py-3">
                                <div class="flex items-center gap-3">
                                    @if ($product->imageUrl())
                                        <img src="{{ $product->imageUrl() }}" alt="" class="h-10 w-10 rounded-lg border border-slate-200 object-cover">
                                    @else
                                        <span class="flex h-10 w-10 items-center justify-center rounded-lg bg-slate-100 text-sm font-semibold text-slate-500">{{ mb_substr($product->name, 0, 1) }}</span>
                                    @endif
                                    <div>
                                        <a href="{{ route('admin.catalog.edit', $product->id) }}" wire:navigate class="font-medium text-slate-900 hover:text-brand-700 hover:underline">{{ $product->name }}</a>
                                        <div class="text-xs text-slate-500">{{ collect([$product->name_bn, $product->brand, $product->barcode])->filter()->join(' · ') }}</div>
                                    </div>
                                </div>
                            </td>
                            <td class="px-4 py-3 text-slate-600">{{ $product->category?->name ?? '—' }}</td>
                            <td class="px-4 py-3 text-slate-600">{{ $product->default_unit }}</td>
                            <td class="px-4 py-3 tabular-nums text-slate-600">{{ $product->variants_count ?: '—' }}</td>
                            <td class="px-4 py-3">
                                <button type="button" wire:click="toggleActive({{ $product->id }})"
                                        class="rounded-full px-2.5 py-0.5 text-xs font-medium ring-1 ring-inset {{ $product->is_active ? 'bg-brand-50 text-brand-700 ring-brand-600/20' : 'bg-slate-100 text-slate-600 ring-slate-500/20' }}"
                                        aria-pressed="{{ $product->is_active ? 'true' : 'false' }}">
                                    {{ $product->is_active ? 'Visible' : 'Hidden' }}
                                </button>
                            </td>
                            <td class="whitespace-nowrap px-4 py-3 text-right">
                                <button type="button" wire:click="delete({{ $product->id }})"
                                        wire:confirm="Remove &quot;{{ $product->name }}&quot; from the catalogue? Shops that already imported it keep their copy."
                                        class="text-sm font-medium text-red-700 hover:underline">Delete</button>
                            </td>
                        </tr>
                    @empty
                        <tr>
                            <td colspan="6" class="px-4 py-12 text-center text-slate-500">
                                @if ($search !== '' || $category !== '')
                                    No catalogue products match.
                                @else
                                    The catalogue is empty. Add products here and shops on a plan with the catalogue can import them.
                                @endif
                            </td>
                        </tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <div class="mt-4">{{ $products->links() }}</div>
</div>
