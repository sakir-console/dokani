<?php

namespace App\Services\Media;

use App\Exceptions\ApiException;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

/**
 * Stores uploaded images safely.
 *
 * The upload is decoded and re-encoded with GD, so whatever is written to
 * disk is a plain JPEG produced by the server: no EXIF, no embedded payloads,
 * a predictable size. The original bytes are never stored.
 */
class ImageStore
{
    public function store(UploadedFile $file, string $directory, int $maxPx, string $disk = 'public'): string
    {
        $bytes = @file_get_contents($file->getRealPath());
        $source = $bytes === false ? false : @imagecreatefromstring($bytes);

        if ($source === false) {
            throw new ApiException('IMAGE_INVALID', __('The file is not a valid image.'), 422, [
                $file->getClientOriginalName() => [__('The file is not a valid image.')],
            ]);
        }

        [$width, $height] = [imagesx($source), imagesy($source)];
        $scale = min(1, $maxPx / max($width, $height));
        [$newWidth, $newHeight] = [max(1, (int) round($width * $scale)), max(1, (int) round($height * $scale))];

        $canvas = imagecreatetruecolor($newWidth, $newHeight);
        // Transparent PNG/WebP areas become white instead of black.
        imagefill($canvas, 0, 0, imagecolorallocate($canvas, 255, 255, 255));
        imagecopyresampled($canvas, $source, 0, 0, 0, 0, $newWidth, $newHeight, $width, $height);

        ob_start();
        imagejpeg($canvas, null, 85);
        $jpeg = (string) ob_get_clean();

        $path = trim($directory, '/').'/'.Str::random(40).'.jpg';
        Storage::disk($disk)->put($path, $jpeg);

        return $path;
    }

    public function delete(?string $path, string $disk = 'public'): void
    {
        if ($path) {
            Storage::disk($disk)->delete($path);
        }
    }
}
