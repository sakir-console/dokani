<?php

namespace App\Services\Sms;

interface SmsSender
{
    /** Send a text message to a normalised Bangladeshi number (01XXXXXXXXX). */
    public function send(string $phone, string $message): void;
}
