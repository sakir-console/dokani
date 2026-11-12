@php
    $nav = [
        ['route' => 'admin.dashboard', 'match' => 'admin.dashboard', 'label' => 'Dashboard', 'icon' => 'M3 12l9-9 9 9M5 10v10h5v-6h4v6h5V10'],
        ['route' => 'admin.shops.index', 'match' => 'admin.shops.*', 'label' => 'Shops', 'icon' => 'M3 9l1.5-5h15L21 9M4 9v11h16V9M9 20v-6h6v6'],
        ['route' => 'admin.catalog.index', 'match' => 'admin.catalog.*', 'label' => 'Catalogue', 'icon' => 'M4 7l8-4 8 4-8 4-8-4zM4 7v10l8 4 8-4V7M12 11v10'],
    ];
@endphp
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>{{ $title ?? 'Admin' }} · {{ config('app.name') }}</title>
    @vite(['resources/css/app.css', 'resources/js/app.js'])
</head>
<body class="min-h-screen bg-slate-50 font-sans text-slate-900 antialiased">
    <div class="lg:flex">
        <aside class="border-b border-slate-200 bg-white lg:sticky lg:top-0 lg:h-screen lg:w-60 lg:shrink-0 lg:border-b-0 lg:border-r">
            <div class="flex items-center justify-between px-4 py-3 lg:block lg:px-5 lg:py-6">
                <a href="{{ route('admin.dashboard') }}" class="flex items-center gap-2.5" wire:navigate>
                    <span class="flex h-9 w-9 items-center justify-center rounded-lg bg-brand-600 text-base font-semibold text-white">দো</span>
                    <span>
                        <span class="block text-sm font-semibold leading-tight">{{ config('app.name') }}</span>
                        <span class="block text-xs leading-tight text-slate-500">Global admin</span>
                    </span>
                </a>

                <form method="POST" action="{{ route('admin.logout') }}" class="lg:hidden">
                    @csrf
                    <button class="rounded-md px-3 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100">Sign out</button>
                </form>
            </div>

            <nav class="flex gap-1 overflow-x-auto px-3 pb-3 lg:block lg:space-y-1 lg:pb-0" aria-label="Main">
                @foreach ($nav as $item)
                    @php $active = request()->routeIs($item['match']); @endphp
                    <a href="{{ route($item['route']) }}" wire:navigate
                       @if ($active) aria-current="page" @endif
                       class="flex shrink-0 items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-medium {{ $active ? 'bg-brand-50 text-brand-700' : 'text-slate-600 hover:bg-slate-100 hover:text-slate-900' }}">
                        <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="{{ $item['icon'] }}"/></svg>
                        {{ $item['label'] }}
                    </a>
                @endforeach
            </nav>

            <div class="absolute bottom-0 hidden w-60 border-t border-slate-200 p-4 lg:block">
                <p class="truncate text-sm font-medium">{{ auth('admin')->user()->name }}</p>
                <p class="truncate text-xs text-slate-500">{{ auth('admin')->user()->email }}</p>
                <form method="POST" action="{{ route('admin.logout') }}" class="mt-3">
                    @csrf
                    <button class="w-full rounded-md border border-slate-200 px-3 py-1.5 text-sm font-medium text-slate-700 hover:bg-slate-50">Sign out</button>
                </form>
            </div>
        </aside>

        <main class="min-w-0 flex-1 px-4 py-6 sm:px-6 lg:px-10 lg:py-8">
            <div class="mx-auto max-w-6xl">
                {{ $slot }}
            </div>
        </main>
    </div>
</body>
</html>
