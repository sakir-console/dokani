<?php

namespace App\Services\Auth;

use App\Enums\OtpPurpose;
use App\Exceptions\ApiException;
use App\Models\OtpCode;
use App\Services\Sms\SmsSender;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

class OtpService
{
    public function __construct(private readonly SmsSender $sms) {}

    /**
     * Create and send a code. Returns false when one was sent too recently.
     */
    public function send(string $phone, OtpPurpose $purpose): bool
    {
        $recent = OtpCode::query()
            ->where('phone', $phone)->where('purpose', $purpose)
            ->where('created_at', '>', now()->subSeconds(config('dokani.otp.resend_after')))
            ->exists();

        if ($recent) {
            return false;
        }

        $length = (int) config('dokani.otp.length');
        $code = str_pad((string) random_int(0, (10 ** $length) - 1), $length, '0', STR_PAD_LEFT);

        DB::transaction(function () use ($phone, $purpose, $code) {
            // Only the newest code for a phone and purpose is ever valid.
            OtpCode::query()->where('phone', $phone)->where('purpose', $purpose)->whereNull('consumed_at')->delete();

            OtpCode::create([
                'phone' => $phone,
                'purpose' => $purpose,
                'code_hash' => Hash::make($code),
                'expires_at' => now()->addMinutes(config('dokani.otp.ttl_minutes')),
            ]);
        });

        $this->sms->send($phone, "Your Dokani verification code is {$code}. It expires in ".config('dokani.otp.ttl_minutes').' minutes.');

        return true;
    }

    /**
     * Check a code and consume it. Throws ApiException when it is wrong,
     * expired, or has been tried too many times.
     */
    public function verify(string $phone, OtpPurpose $purpose, string $code): void
    {
        $invalid = new ApiException('OTP_INVALID', __('The verification code is incorrect or has expired.'), 422, [
            'otp' => [__('The verification code is incorrect or has expired.')],
        ]);

        // Counting the attempt and checking the code happen under a row lock,
        // so parallel guesses cannot exceed the attempt limit.
        $ok = DB::transaction(function () use ($phone, $purpose, $code) {
            $otp = OtpCode::query()
                ->where('phone', $phone)->where('purpose', $purpose)
                ->whereNull('consumed_at')
                ->latest('id')->lockForUpdate()->first();

            if ($otp === null || $otp->expires_at->isPast() || $otp->attempts >= config('dokani.otp.max_attempts')) {
                return false;
            }

            $otp->increment('attempts');

            if (! Hash::check($code, $otp->code_hash)) {
                return false;
            }

            $otp->update(['consumed_at' => now()]);

            return true;
        });

        if (! $ok) {
            throw $invalid;
        }
    }
}
