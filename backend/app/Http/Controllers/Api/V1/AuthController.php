<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\OtpPurpose;
use App\Exceptions\ApiException;
use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\ChangePasswordRequest;
use App\Http\Requests\Api\V1\ForgotPasswordRequest;
use App\Http\Requests\Api\V1\LoginRequest;
use App\Http\Requests\Api\V1\RegisterRequest;
use App\Http\Requests\Api\V1\ResetPasswordRequest;
use App\Http\Resources\SessionResource;
use App\Models\ShopUser;
use App\Models\User;
use App\Services\Audit\AuditLogger;
use App\Services\Auth\OtpService;
use App\Services\Auth\RegisterShop;
use App\Support\Phone;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

class AuthController extends Controller
{
    public function register(RegisterRequest $request, RegisterShop $registerShop): JsonResponse
    {
        [$user, $shop] = $registerShop->handle($request->validated(), $request->file('logo'));

        $token = $user->createToken($request->string('device_name')->toString())->plainTextToken;
        $membership = ShopUser::query()->where('shop_id', $shop->id)->where('user_id', $user->id)->first();

        return response()->json([
            'data' => ['token' => $token] + (new SessionResource($user, $shop, $membership))->resolve($request),
        ], 201);
    }

    public function login(LoginRequest $request): JsonResponse
    {
        $phone = Phone::normalize($request->string('phone')->toString());
        $user = $phone ? User::query()->where('phone', $phone)->first() : null;

        // Same answer for an unknown phone and a wrong password, so the
        // endpoint cannot be used to discover which numbers are registered.
        if ($user === null || ! Hash::check($request->string('password')->toString(), $user->password)) {
            throw new ApiException('INVALID_CREDENTIALS', __('The phone number or password is incorrect.'), 422);
        }

        if (! $user->is_active) {
            throw ApiException::forbidden('ACCOUNT_DISABLED', __('This account has been disabled.'));
        }

        $membership = ShopUser::query()
            ->where('user_id', $user->id)->where('is_active', true)
            ->whereHas('shop')->with('shop')->orderBy('id')->first();

        if ($membership === null) {
            throw ApiException::forbidden('NO_SHOP', __('This account is not linked to any shop.'));
        }

        $user->forceFill(['last_login_at' => now()])->save();
        $token = $user->createToken($request->string('device_name')->toString())->plainTextToken;

        return response()->json([
            'data' => ['token' => $token] + (new SessionResource($user, $membership->shop, $membership))->resolve($request),
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['data' => ['message' => __('Logged out.')]]);
    }

    public function forgotPassword(ForgotPasswordRequest $request, OtpService $otp): JsonResponse
    {
        $phone = Phone::normalize($request->string('phone')->toString());

        if (User::query()->where('phone', $phone)->where('is_active', true)->exists()) {
            $otp->send($phone, OtpPurpose::ResetPassword);
        }

        // Always the same answer, whether or not the number is registered.
        return response()->json(['data' => [
            'message' => __('If this number is registered, a verification code has been sent.'),
            'expires_in' => config('dokani.otp.ttl_minutes') * 60,
        ]]);
    }

    public function resetPassword(ResetPasswordRequest $request, OtpService $otp, AuditLogger $audit): JsonResponse
    {
        $phone = Phone::normalize($request->string('phone')->toString());

        $otp->verify($phone, OtpPurpose::ResetPassword, $request->string('otp')->toString());

        $user = User::query()->where('phone', $phone)->first();
        if ($user === null) {
            throw new ApiException('OTP_INVALID', __('The verification code is incorrect or has expired.'), 422);
        }

        DB::transaction(function () use ($user, $request, $audit) {
            $user->forceFill([
                'password' => $request->string('password')->toString(),
                'phone_verified_at' => $user->phone_verified_at ?? now(),
            ])->save();

            // A reset signs every device out.
            $user->tokens()->delete();
            $audit->log('user.password_reset', $user, actor: $user);
        });

        return response()->json(['data' => ['message' => __('Your password has been reset. Please log in.')]]);
    }

    public function changePassword(ChangePasswordRequest $request, AuditLogger $audit): JsonResponse
    {
        $user = $request->user();

        if (! Hash::check($request->string('current_password')->toString(), $user->password)) {
            throw new ApiException('CURRENT_PASSWORD_INCORRECT', __('The current password is incorrect.'), 422, [
                'current_password' => [__('The current password is incorrect.')],
            ]);
        }

        DB::transaction(function () use ($user, $request, $audit) {
            $user->forceFill(['password' => $request->string('password')->toString()])->save();

            // Other devices are signed out; this one stays.
            $user->tokens()->where('id', '!=', $user->currentAccessToken()->id)->delete();
            $audit->log('user.password_changed', $user);
        });

        return response()->json(['data' => ['message' => __('Your password has been changed.')]]);
    }
}
