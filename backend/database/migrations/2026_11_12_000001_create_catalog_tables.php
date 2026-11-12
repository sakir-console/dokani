<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // shop_id NULL = built-in unit shared by every shop; otherwise a shop's own unit.
        Schema::create('units', function (Blueprint $table) {
            $table->id();
            $table->foreignId('shop_id')->nullable()->constrained()->restrictOnDelete();
            $table->string('name', 40);
            $table->string('name_bn', 40)->nullable();
            $table->string('short_name', 12);
            // Whether quantities like 0.250 are allowed (kg, litre, metre) or only whole numbers (piece, box).
            $table->boolean('allows_decimal')->default(false);
            $table->timestamps();

            $table->index(['shop_id', 'name']);
        });

        Schema::create('brands', function (Blueprint $table) {
            $table->id();
            $table->foreignId('shop_id')->constrained()->restrictOnDelete();
            $table->string('name', 100);
            $table->timestamps();
            $table->softDeletes();

            $table->index(['shop_id', 'name']);
        });

        Schema::create('vendors', function (Blueprint $table) {
            $table->id();
            $table->foreignId('shop_id')->constrained()->restrictOnDelete();
            $table->string('name', 120);
            $table->string('phone', 15)->nullable();
            $table->string('company_name', 150)->nullable();
            $table->string('address')->nullable();
            $table->text('notes')->nullable();
            $table->timestamps();
            $table->softDeletes();

            $table->index(['shop_id', 'name']);
            $table->index(['shop_id', 'phone']);
        });

        // Global catalogue: managed by the platform admin, shared by all shops.
        // Holds no prices and no stock.
        Schema::create('global_categories', function (Blueprint $table) {
            $table->id();
            $table->string('name', 100);
            $table->string('name_bn', 100)->nullable();
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->timestamps();
        });

        Schema::create('global_products', function (Blueprint $table) {
            $table->id();
            $table->foreignId('global_category_id')->nullable()->constrained()->nullOnDelete();
            $table->string('name', 190);
            $table->string('name_bn', 190)->nullable();
            $table->string('brand', 100)->nullable();
            $table->text('description')->nullable();
            $table->string('default_unit', 40)->default('Piece');
            $table->string('image_path')->nullable();
            $table->string('barcode', 64)->nullable()->index();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->softDeletes();

            $table->index('name');
        });

        Schema::create('global_product_variants', function (Blueprint $table) {
            $table->id();
            $table->foreignId('global_product_id')->constrained()->cascadeOnDelete();
            $table->string('name', 120);
            // e.g. {"size": "M", "color": "Red"}. Named "options" because Eloquent reserves "attributes".
            $table->json('options')->nullable();
            $table->string('barcode', 64)->nullable();
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->timestamps();
        });

        Schema::create('products', function (Blueprint $table) {
            $table->id();
            $table->foreignId('shop_id')->constrained()->restrictOnDelete();
            // Reference only: where the product was imported from. Never synced back.
            $table->foreignId('global_product_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('category_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('brand_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('unit_id')->constrained()->restrictOnDelete();
            $table->foreignId('vendor_id')->nullable()->constrained()->nullOnDelete();
            $table->string('name', 190);
            $table->text('description')->nullable();
            $table->string('image_path')->nullable();
            $table->string('storage_location', 100)->nullable();
            // False = one hidden default variant.
            $table->boolean('has_variants')->default(false);
            // NULL = use the shop's default threshold.
            $table->decimal('low_stock_threshold', 14, 3)->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->softDeletes();

            $table->index(['shop_id', 'name']);
            $table->index(['shop_id', 'category_id']);
            $table->index(['shop_id', 'brand_id']);
            $table->index(['shop_id', 'vendor_id']);
            $table->index(['shop_id', 'updated_at']);
        });

        // The sellable, stock-holding unit. Every product has at least one.
        Schema::create('product_variants', function (Blueprint $table) {
            $table->id();
            $table->foreignId('shop_id')->constrained()->restrictOnDelete();
            $table->foreignId('product_id')->constrained()->restrictOnDelete();
            $table->string('name', 120)->nullable();
            // e.g. {"size": "M", "color": "Red"}. Exposed by the API as "attributes".
            $table->json('options')->nullable();
            $table->string('sku', 64)->nullable();
            $table->decimal('purchase_price', 14, 2)->default(0);
            $table->decimal('selling_price', 14, 2)->default(0);
            // Cached balance. Changed only by StockService, together with a stock_movements row.
            $table->decimal('stock_quantity', 14, 3)->default(0);
            $table->boolean('is_default')->default(false);
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->softDeletes();

            $table->index(['shop_id', 'product_id']);
            $table->index(['shop_id', 'sku']);
            $table->index(['shop_id', 'stock_quantity']);
            $table->index(['shop_id', 'updated_at']);
        });

        Schema::create('barcodes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('shop_id')->constrained()->restrictOnDelete();
            $table->foreignId('product_variant_id')->constrained()->cascadeOnDelete();
            $table->string('code', 64);
            $table->timestamps();

            // One code resolves to exactly one variant inside a shop.
            $table->unique(['shop_id', 'code']);
        });

        // Append-only history of every stock change.
        Schema::create('stock_movements', function (Blueprint $table) {
            $table->id();
            $table->foreignId('shop_id')->constrained()->restrictOnDelete();
            $table->foreignId('product_variant_id')->constrained()->restrictOnDelete();
            $table->string('type', 20);
            // Signed: negative for stock leaving the shop.
            $table->decimal('quantity', 14, 3);
            $table->decimal('balance_after', 14, 3);
            $table->decimal('unit_cost', 14, 2)->nullable();
            $table->foreignId('vendor_id')->nullable()->constrained()->nullOnDelete();
            $table->nullableMorphs('reference');
            $table->string('note')->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('created_at')->useCurrent();

            $table->index(['shop_id', 'product_variant_id', 'id']);
            $table->index(['shop_id', 'vendor_id', 'id']);
            $table->index(['shop_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('stock_movements');
        Schema::dropIfExists('barcodes');
        Schema::dropIfExists('product_variants');
        Schema::dropIfExists('products');
        Schema::dropIfExists('global_product_variants');
        Schema::dropIfExists('global_products');
        Schema::dropIfExists('global_categories');
        Schema::dropIfExists('vendors');
        Schema::dropIfExists('brands');
        Schema::dropIfExists('units');
    }
};
