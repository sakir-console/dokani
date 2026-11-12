<?php

use App\Http\Controllers\PublicInvoiceController;
use Illuminate\Support\Facades\Route;

/*
| Pages reachable without any login.
|
| Loaded without the "web" middleware group on purpose: no session is started
| and no cookie is set, so a public hit never writes to the sessions table.
| The unguessable token in the URL is the only credential.
*/

// The page a customer reaches by scanning the QR code on a receipt.
Route::get('i/{token}', [PublicInvoiceController::class, 'show'])->name('invoice.public');
Route::get('i/{token}/pdf', [PublicInvoiceController::class, 'pdf'])->name('invoice.public.pdf');
