<?php

use Illuminate\Support\Facades\Route;

// The public site has no pages of its own yet; the root sends operators to the admin panel.
// Public invoice pages (/i/{token}) are added in Phase 3.
Route::redirect('/', '/admin');
