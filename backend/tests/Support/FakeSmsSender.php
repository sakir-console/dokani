<?php

namespace Tests\Support;

use App\Services\Sms\SmsSender;

class FakeSmsSender implements SmsSender
{
    /** @var list<array{phone: string, message: string}> */
    public array $sent = [];

    public function send(string $phone, string $message): void
    {
        $this->sent[] = ['phone' => $phone, 'message' => $message];
    }

    /** The numeric code in the last message sent to this phone. */
    public function lastCodeFor(string $phone): ?string
    {
        foreach (array_reverse($this->sent) as $sms) {
            if ($sms['phone'] === $phone && preg_match('/\b(\d{4,8})\b/', $sms['message'], $m)) {
                return $m[1];
            }
        }

        return null;
    }
}
