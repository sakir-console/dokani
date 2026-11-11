<?php

namespace App\Services\Audit;

use App\Models\Admin;
use App\Models\AuditLog;
use App\Models\User;
use App\Services\Tenancy\TenantContext;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Auth;

class AuditLogger
{
    /**
     * @param  array<string, mixed>|null  $old
     * @param  array<string, mixed>|null  $new
     */
    public function log(string $action, ?Model $subject = null, ?array $old = null, ?array $new = null, ?int $shopId = null, ?User $actor = null): AuditLog
    {
        // $actor is for the few cases where the user is known but not signed in yet (registration, password reset).
        [$actorType, $actorId] = $actor ? ['user', $actor->id] : $this->actor();
        $request = app()->runningInConsole() && ! app()->runningUnitTests() ? null : request();

        return AuditLog::create([
            // Resolved at call time: the tenant context is request-scoped.
            'shop_id' => $shopId ?? app(TenantContext::class)->idOrNull(),
            'actor_type' => $actorType,
            'actor_id' => $actorId,
            'action' => $action,
            'subject_type' => $subject?->getMorphClass(),
            'subject_id' => $subject?->getKey(),
            'old_values' => $old,
            'new_values' => $new,
            'ip' => $request?->ip(),
            'user_agent' => $request ? mb_substr((string) $request->userAgent(), 0, 255) : null,
        ]);
    }

    /** @return array{0: string, 1: int|null} */
    private function actor(): array
    {
        if (($admin = Auth::guard('admin')->user()) instanceof Admin) {
            return ['admin', $admin->id];
        }
        if (($user = Auth::guard('sanctum')->user()) instanceof User) {
            return ['user', $user->id];
        }

        return ['system', null];
    }
}
