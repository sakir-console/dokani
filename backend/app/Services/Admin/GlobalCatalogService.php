<?php

namespace App\Services\Admin;

use App\Models\GlobalProduct;
use App\Services\Audit\AuditLogger;
use App\Services\Media\ImageStore;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;

/**
 * Admin-side management of the global catalogue.
 * Global products carry no price and no stock, and changing one never
 * touches the copies shops have already imported.
 */
class GlobalCatalogService
{
    public function __construct(private readonly ImageStore $images, private readonly AuditLogger $audit) {}

    /**
     * @param  array<string, mixed>  $data
     * @param  list<array{id?: ?int, name: string, barcode?: ?string}>  $variants  the complete set
     */
    public function save(?GlobalProduct $product, array $data, array $variants, ?UploadedFile $image = null): GlobalProduct
    {
        $newImage = $image ? $this->images->store($image, 'global-products', config('dokani.uploads.product_image_max_px')) : null;
        $oldImage = null;

        try {
            $saved = DB::transaction(function () use ($product, $data, $variants, $newImage, &$oldImage) {
                $creating = $product === null;
                $product ??= new GlobalProduct;
                $product->fill($data);

                if ($newImage !== null) {
                    $oldImage = $product->image_path;
                    $product->image_path = $newImage;
                }
                $product->save();

                $keep = [];
                foreach (array_values($variants) as $order => $row) {
                    $attributes = ['name' => trim($row['name']), 'barcode' => ($row['barcode'] ?? '') ?: null, 'sort_order' => $order];
                    $existing = isset($row['id']) ? $product->variants()->find($row['id']) : null;

                    $keep[] = $existing
                        ? tap($existing)->update($attributes)->id
                        : $product->variants()->create($attributes)->id;
                }
                $product->variants()->whereNotIn('id', $keep)->delete();

                $this->audit->log($creating ? 'global_product.created' : 'global_product.updated', $product, null, ['name' => $product->name]);

                return $product;
            });
        } catch (\Throwable $e) {
            $this->images->delete($newImage);

            throw $e;
        }

        $this->images->delete($oldImage);

        return $saved;
    }

    public function delete(GlobalProduct $product): void
    {
        // Soft delete: shops that imported it keep their copy and its reference.
        $product->delete();
        $this->audit->log('global_product.deleted', $product, ['name' => $product->name]);
    }
}
