<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Phones that use a shop. Identifies where an offline sale came from
        // and when each phone last synced.
        Schema::create('devices', function (Blueprint $table) {
            $table->id();
            $table->foreignId('shop_id')->constrained()->restrictOnDelete();
            $table->foreignId('user_id')->constrained()->restrictOnDelete();
            $table->uuid('device_uuid');
            $table->string('name', 100)->nullable();
            $table->string('platform', 20)->nullable();
            $table->string('app_version', 20)->nullable();
            $table->timestamp('last_seen_at')->nullable();
            $table->timestamp('last_synced_at')->nullable();
            $table->timestamps();

            $table->unique(['shop_id', 'device_uuid']);
        });

        // Things the shop owner should look at, e.g. an offline sale that took stock below zero.
        Schema::create('shop_notifications', function (Blueprint $table) {
            $table->id();
            $table->foreignId('shop_id')->constrained()->restrictOnDelete();
            $table->string('type', 40);
            $table->string('title');
            $table->string('body', 500)->nullable();
            $table->json('data')->nullable();
            $table->timestamp('read_at')->nullable();
            $table->timestamps();

            $table->index(['shop_id', 'read_at', 'id']);
        });

        Schema::table('sales', function (Blueprint $table) {
            $table->foreignId('device_id')->nullable()->after('created_by')->constrained()->nullOnDelete();
        });

        // Delta sync asks "what changed since X" and must also hear about deletions.
        Schema::table('customers', function (Blueprint $table) {
            $table->index(['shop_id', 'updated_at']);
        });
    }

    public function down(): void
    {
        Schema::table('customers', fn (Blueprint $table) => $table->dropIndex(['shop_id', 'updated_at']));
        Schema::table('sales', fn (Blueprint $table) => $table->dropConstrainedForeignId('device_id'));
        Schema::dropIfExists('shop_notifications');
        Schema::dropIfExists('devices');
    }
};
