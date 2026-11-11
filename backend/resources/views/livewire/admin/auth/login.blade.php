<div class="w-full max-w-sm">
    <div class="mb-6 text-center">
        <span class="mx-auto flex h-12 w-12 items-center justify-center rounded-xl bg-brand-600 text-xl font-semibold text-white">দো</span>
        <h1 class="mt-4 text-xl font-semibold">{{ config('app.name') }} admin</h1>
        <p class="mt-1 text-sm text-slate-500">Sign in to manage shops and subscriptions.</p>
    </div>

    <form wire:submit="login" class="space-y-4 rounded-xl border border-slate-200 bg-white p-6">
        <div>
            <label for="email" class="block text-sm font-medium text-slate-700">Email</label>
            <input id="email" type="email" wire:model="email" autocomplete="username" autofocus required
                   class="mt-1 block w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20">
            @error('email') <p class="mt-1 text-sm text-red-600" role="alert">{{ $message }}</p> @enderror
        </div>

        <div>
            <label for="password" class="block text-sm font-medium text-slate-700">Password</label>
            <input id="password" type="password" wire:model="password" autocomplete="current-password" required
                   class="mt-1 block w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20">
            @error('password') <p class="mt-1 text-sm text-red-600" role="alert">{{ $message }}</p> @enderror
        </div>

        <label class="flex items-center gap-2 text-sm text-slate-600">
            <input type="checkbox" wire:model="remember" class="h-4 w-4 rounded border-slate-300 text-brand-600">
            Keep me signed in
        </label>

        <button type="submit" wire:loading.attr="disabled"
                class="flex w-full items-center justify-center rounded-lg bg-brand-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-600/40 disabled:opacity-60">
            <span wire:loading.remove wire:target="login">Sign in</span>
            <span wire:loading wire:target="login">Signing in…</span>
        </button>
    </form>
</div>
