<?php

use Illuminate\Support\Facades\Route;

// The public site has no pages of its own yet; the root sends operators to the admin panel.
Route::redirect('/', '/admin');
