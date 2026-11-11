<?php

return [

    /*
    | Role → permissions. '*' grants everything.
    | Enforced by the RequirePermission middleware; the app only mirrors it.
    */
    'roles' => [
        'owner' => ['*'],
        'manager' => [
            'shop.view', 'catalog.manage', 'inventory.manage', 'vendors.manage',
            'customers.manage', 'pos.sell', 'pos.price_override', 'sales.void',
            'due.collect', 'reports.view',
        ],
        'cashier' => ['shop.view', 'pos.sell', 'customers.manage', 'due.collect'],
    ],

    'otp' => [
        'length' => 6,
        'ttl_minutes' => 5,
        'max_attempts' => 5,
        // Seconds a phone must wait before asking for another code.
        'resend_after' => 60,
    ],

    'sms' => [
        // "log" writes messages to the application log (development only).
        // A real gateway driver needs credentials; see docs/06-setup.md.
        'driver' => env('SMS_DRIVER', 'log'),
    ],

    'password_min_length' => 8,

    'uploads' => [
        'logo_max_kb' => 2048,
        'logo_max_px' => 512,
    ],

    'app' => [
        // Oldest mobile app version the API still accepts.
        'min_version' => env('APP_MIN_VERSION', '1.0.0'),
    ],

];
