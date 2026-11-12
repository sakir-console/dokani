<?php

use App\Livewire\Admin\Auth\Login;
use App\Livewire\Admin\Catalog\Form as CatalogForm;
use App\Livewire\Admin\Catalog\Index as CatalogIndex;
use App\Livewire\Admin\Dashboard;
use App\Livewire\Admin\Shops\Index as ShopsIndex;
use App\Livewire\Admin\Shops\Show as ShopsShow;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Route;

/*
| Global Admin panel. Mounted at /admin with the "admin." route name prefix.
| Uses the "admin" session guard, which reads the admins table only.
*/

Route::livewire('login', Login::class)->name('login');

Route::middleware('admin')->group(function () {
    Route::livewire('/', Dashboard::class)->name('dashboard');
    Route::livewire('shops', ShopsIndex::class)->name('shops.index');
    Route::livewire('shops/{shopId}', ShopsShow::class)->whereNumber('shopId')->name('shops.show');

    Route::livewire('catalog', CatalogIndex::class)->name('catalog.index');
    Route::livewire('catalog/create', CatalogForm::class)->name('catalog.create');
    Route::livewire('catalog/{productId}/edit', CatalogForm::class)->whereNumber('productId')->name('catalog.edit');

    Route::post('logout', function (Request $request) {
        Auth::guard('admin')->logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();

        return redirect()->route('admin.login');
    })->name('logout');
});
