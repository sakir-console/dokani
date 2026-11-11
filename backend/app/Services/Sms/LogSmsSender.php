<?php

namespace App\Services\Sms;

use Illuminate\Support\Facades\Log;

/**
 * Development driver: writes the message to the log instead of sending it.
 * Never use in production — OTP codes would be readable in the log file.
 */
class LogSmsSender implements SmsSender
{
    public function send(string $phone, string $message): void
    {
        Log::channel(config('logging.default'))->info('SMS (log driver, not sent)', [
            'phone' => $phone,
            'message' => $message,
        ]);
    }
}
