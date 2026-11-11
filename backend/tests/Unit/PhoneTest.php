<?php

namespace Tests\Unit;

use App\Support\Phone;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

class PhoneTest extends TestCase
{
    #[DataProvider('validNumbers')]
    public function test_it_normalizes_valid_numbers(string $input): void
    {
        $this->assertSame('01712345678', Phone::normalize($input));
    }

    public static function validNumbers(): array
    {
        return [
            'local' => ['01712345678'],
            'plus country code' => ['+8801712345678'],
            'country code' => ['8801712345678'],
            'spaces and dashes' => ['017 1234-5678'],
            'bengali digits' => ['০১৭১২৩৪৫৬৭৮'],
            'padded' => ['  01712345678 '],
        ];
    }

    #[DataProvider('invalidNumbers')]
    public function test_it_rejects_invalid_numbers(?string $input): void
    {
        $this->assertNull(Phone::normalize($input));
    }

    public static function invalidNumbers(): array
    {
        return [
            'null' => [null],
            'empty' => [''],
            'too short' => ['0171234567'],
            'too long' => ['017123456789'],
            'bad operator prefix' => ['01212345678'],
            'landline' => ['0212345678'],
            'letters' => ['01712abc678'],
            'other country' => ['+911712345678'],
        ];
    }

    public function test_it_masks_a_number(): void
    {
        $this->assertSame('017*****678', Phone::mask('01712345678'));
    }
}
