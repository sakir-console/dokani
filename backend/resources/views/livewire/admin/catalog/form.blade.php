@php
    $input = 'mt-1 block w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20';
    $label = 'block text-sm font-medium text-slate-700';
@endphp
<div class="max-w-3xl">
    <a href="{{ route('admin.catalog.index') }}" wire:navigate class="text-sm font-medium text-slate-500 hover:text-slate-900">← Global catalogue</a>
    <h1 class="mt-3 text-2xl font-semibold">{{ $productId ? 'Edit catalogue product' : 'New catalogue product' }}</h1>
    <p class="mt-1 text-sm text-slate-500">No price or stock here. Each shop sets those when it imports the product.</p>

    <form wire:submit="save" class="mt-6 space-y-6">
        <section class="space-y-4 rounded-xl border border-slate-200 bg-white p-5">
            <div class="grid gap-4 sm:grid-cols-2">
                <div>
                    <label for="name" class="{{ $label }}">Name</label>
                    <input id="name" type="text" wire:model="name" maxlength="190" required class="{{ $input }}">
                    @error('name') <p class="mt-1 text-sm text-red-600" role="alert">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label for="name_bn" class="{{ $label }}">Name in Bangla <span class="font-normal text-slate-500">(optional)</span></label>
                    <input id="name_bn" type="text" wire:model="name_bn" maxlength="190" lang="bn" class="{{ $input }}">
                    @error('name_bn') <p class="mt-1 text-sm text-red-600" role="alert">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label for="brand" class="{{ $label }}">Brand <span class="font-normal text-slate-500">(optional)</span></label>
                    <input id="brand" type="text" wire:model="brand" maxlength="100" class="{{ $input }}">
                    @error('brand') <p class="mt-1 text-sm text-red-600" role="alert">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label for="default_unit" class="{{ $label }}">Default unit</label>
                    <select id="default_unit" wire:model="default_unit" class="{{ $input }}">
                        @foreach ($units as $unit)
                            <option value="{{ $unit }}">{{ $unit }}</option>
                        @endforeach
                    </select>
                    @error('default_unit') <p class="mt-1 text-sm text-red-600" role="alert">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label for="category_id" class="{{ $label }}">Category <span class="font-normal text-slate-500">(optional)</span></label>
                    <select id="category_id" wire:model="category_id" class="{{ $input }}">
                        <option value="">No category</option>
                        @foreach ($categories as $category)
                            <option value="{{ $category->id }}">{{ $category->name }}</option>
                        @endforeach
                    </select>
                    @error('category_id') <p class="mt-1 text-sm text-red-600" role="alert">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label for="new_category" class="{{ $label }}">Or add a category</label>
                    <div class="mt-1 flex gap-2">
                        <input id="new_category" type="text" wire:model="new_category" wire:keydown.enter.prevent="addCategory" maxlength="100"
                               class="block w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20">
                        <button type="button" wire:click="addCategory" class="shrink-0 rounded-lg border border-slate-300 px-3 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50">Add</button>
                    </div>
                    @error('new_category') <p class="mt-1 text-sm text-red-600" role="alert">{{ $message }}</p> @enderror
                </div>
                <div class="sm:col-span-2">
                    <label for="barcode" class="{{ $label }}">Barcode <span class="font-normal text-slate-500">(optional; for a product without variants)</span></label>
                    <input id="barcode" type="text" wire:model="barcode" maxlength="64" inputmode="numeric" class="{{ $input }}">
                    @error('barcode') <p class="mt-1 text-sm text-red-600" role="alert">{{ $message }}</p> @enderror
                </div>
                <div class="sm:col-span-2">
                    <label for="description" class="{{ $label }}">Description <span class="font-normal text-slate-500">(optional)</span></label>
                    <textarea id="description" wire:model="description" rows="3" maxlength="2000" class="{{ $input }}"></textarea>
                    @error('description') <p class="mt-1 text-sm text-red-600" role="alert">{{ $message }}</p> @enderror
                </div>
            </div>
        </section>

        <section class="rounded-xl border border-slate-200 bg-white p-5">
            <h2 class="text-base font-semibold">Image</h2>
            <div class="mt-3 flex items-center gap-4">
                @if ($image && method_exists($image, 'isPreviewable') && $image->isPreviewable())
                    <img src="{{ $image->temporaryUrl() }}" alt="New image preview" class="h-20 w-20 rounded-lg border border-slate-200 object-cover">
                @elseif ($currentImageUrl)
                    <img src="{{ $currentImageUrl }}" alt="Current image" class="h-20 w-20 rounded-lg border border-slate-200 object-cover">
                @endif
                <div>
                    <label for="image" class="sr-only">Product image</label>
                    <input id="image" type="file" wire:model="image" accept="image/jpeg,image/png,image/webp" class="block text-sm text-slate-600 file:mr-3 file:rounded-lg file:border-0 file:bg-slate-100 file:px-3 file:py-2 file:text-sm file:font-medium file:text-slate-700 hover:file:bg-slate-200">
                    <p class="mt-1 text-xs text-slate-500">JPG, PNG or WebP, up to 4 MB. Resized to 800px.</p>
                    <p wire:loading wire:target="image" class="mt-1 text-xs text-slate-500">Uploading…</p>
                    @error('image') <p class="mt-1 text-sm text-red-600" role="alert">{{ $message }}</p> @enderror
                </div>
            </div>
        </section>

        <section class="rounded-xl border border-slate-200 bg-white p-5">
            <div class="flex items-center justify-between">
                <div>
                    <h2 class="text-base font-semibold">Variants</h2>
                    <p class="text-sm text-slate-500">Sizes, weights or models, for example 250ml, 500ml, 1L. Leave empty for a single product.</p>
                </div>
                <button type="button" wire:click="addVariant" class="shrink-0 rounded-lg border border-slate-300 px-3 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50">Add variant</button>
            </div>

            <div class="mt-4 space-y-3">
                @foreach ($variants as $index => $variant)
                    <div wire:key="variant-{{ $index }}" class="grid gap-3 sm:grid-cols-[1fr_1fr_auto]">
                        <div>
                            <label for="variant-name-{{ $index }}" class="sr-only">Variant {{ $index + 1 }} name</label>
                            <input id="variant-name-{{ $index }}" type="text" wire:model="variants.{{ $index }}.name" placeholder="Name, e.g. 500ml" maxlength="120" class="{{ $input }} mt-0">
                            @error("variants.$index.name") <p class="mt-1 text-sm text-red-600" role="alert">{{ $message }}</p> @enderror
                        </div>
                        <div>
                            <label for="variant-barcode-{{ $index }}" class="sr-only">Variant {{ $index + 1 }} barcode</label>
                            <input id="variant-barcode-{{ $index }}" type="text" wire:model="variants.{{ $index }}.barcode" placeholder="Barcode (optional)" maxlength="64" class="{{ $input }} mt-0">
                            @error("variants.$index.barcode") <p class="mt-1 text-sm text-red-600" role="alert">{{ $message }}</p> @enderror
                        </div>
                        <button type="button" wire:click="removeVariant({{ $index }})" class="rounded-lg px-3 py-2 text-sm font-medium text-red-700 hover:bg-red-50">Remove</button>
                    </div>
                @endforeach
            </div>
        </section>

        <label class="flex items-center gap-2 text-sm text-slate-700">
            <input type="checkbox" wire:model="is_active" class="h-4 w-4 rounded border-slate-300 text-brand-600">
            Visible to shops
        </label>

        <div class="flex gap-2">
            <button type="submit" wire:loading.attr="disabled" wire:target="save,image"
                    class="rounded-lg bg-brand-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-brand-700 disabled:opacity-60">
                {{ $productId ? 'Save changes' : 'Add to catalogue' }}
            </button>
            <a href="{{ route('admin.catalog.index') }}" wire:navigate class="rounded-lg px-4 py-2.5 text-sm font-medium text-slate-600 hover:bg-slate-100">Cancel</a>
        </div>
    </form>
</div>
