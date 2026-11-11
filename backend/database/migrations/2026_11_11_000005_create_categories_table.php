<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // First tenant-owned table. Every shop-owned table follows this shape:
        // shop_id NOT NULL, foreign key to shops, shop_id leading the indexes.
        Schema::create('categories', function (Blueprint $table) {
            $table->id();
            $table->foreignId('shop_id')->constrained()->restrictOnDelete();
            $table->foreignId('parent_id')->nullable()->constrained('categories')->restrictOnDelete();
            $table->string('name', 100);
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->timestamps();
            $table->softDeletes();

            $table->index(['shop_id', 'parent_id', 'name']);
            $table->index(['shop_id', 'updated_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('categories');
    }
};
