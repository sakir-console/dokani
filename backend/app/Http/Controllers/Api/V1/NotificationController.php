<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\ShopNotification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class NotificationController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $page = ShopNotification::query()
            ->when($request->boolean('unread'), fn ($q) => $q->whereNull('read_at'))
            ->latest('id')
            ->paginate(min($request->integer('per_page', 30), 100));

        return response()->json([
            'data' => collect($page->items())->map(fn (ShopNotification $n) => [
                'id' => $n->id,
                'type' => $n->type,
                'title' => $n->title,
                'body' => $n->body,
                'data' => $n->data,
                'read' => $n->read_at !== null,
                'created_at' => $n->created_at?->toIso8601String(),
            ]),
            'meta' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'unread' => ShopNotification::query()->whereNull('read_at')->count(),
            ],
        ]);
    }

    public function markRead(ShopNotification $notification): JsonResponse
    {
        $notification->forceFill(['read_at' => $notification->read_at ?? now()])->save();

        return response()->json(null, 204);
    }

    public function markAllRead(): JsonResponse
    {
        ShopNotification::query()->whereNull('read_at')->update(['read_at' => now()]);

        return response()->json(null, 204);
    }
}
