<?php

namespace App\Providers;

use App\Services\Sms\LogSmsSender;
use App\Services\Sms\SmsSender;
use App\Services\Subscription\Entitlements;
use App\Services\Tenancy\TenantContext;
use App\Support\Phone;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;
use InvalidArgumentException;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        // Scoped: one instance per request or queued job, never shared between them.
        $this->app->scoped(TenantContext::class);
        $this->app->scoped(Entitlements::class);

        $this->app->bind(SmsSender::class, fn () => match (config('dokani.sms.driver')) {
            'log' => new LogSmsSender,
            default => throw new InvalidArgumentException('Unknown SMS driver ['.config('dokani.sms.driver').'].'),
        });
    }

    public function boot(): void
    {
        // Lazy loading and silently dropped attributes are bugs; surface them outside production.
        Model::shouldBeStrict(! $this->app->isProduction());

        $this->configureRateLimiting();
    }

    private function configureRateLimiting(): void
    {
        RateLimiter::for('api', fn (Request $request) => Limit::perMinute(120)->by($request->user()?->id ?: $request->ip()));

        // Login, registration, password reset: limited per phone and per IP.
        RateLimiter::for('auth', function (Request $request) {
            $phone = Phone::normalize((string) $request->input('phone')) ?? 'unknown';

            return [
                Limit::perMinute(5)->by('auth:phone:'.$phone),
                Limit::perMinute(20)->by('auth:ip:'.$request->ip()),
            ];
        });

        // Each OTP costs an SMS, so sending is limited much harder.
        RateLimiter::for('otp', function (Request $request) {
            $phone = Phone::normalize((string) $request->input('phone')) ?? 'unknown';

            return [
                Limit::perHour(5)->by('otp:phone:'.$phone),
                Limit::perHour(30)->by('otp:ip:'.$request->ip()),
            ];
        });

        // Public invoice links: generous for a customer, useless for guessing 256-bit tokens.
        RateLimiter::for('public-invoice', fn (Request $request) => Limit::perMinute(30)->by('invoice:'.$request->ip()));

        RateLimiter::for('admin-login', fn (Request $request) => Limit::perMinute(5)->by('admin:'.$request->ip()));
    }
}
