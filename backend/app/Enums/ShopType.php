<?php

namespace App\Enums;

enum ShopType: string
{
    case Grocery = 'grocery';
    case SuperShop = 'super_shop';
    case Clothing = 'clothing';
    case Cosmetics = 'cosmetics';
    case Electronics = 'electronics';
    case Pharmacy = 'pharmacy';
    case Stationery = 'stationery';
    case Hardware = 'hardware';
    case FruitVegetable = 'fruit_vegetable';
    case MobileAccessories = 'mobile_accessories';
    case General = 'general';

    public function label(): string
    {
        return match ($this) {
            self::Grocery => 'Grocery store',
            self::SuperShop => 'Super shop',
            self::Clothing => 'Clothing store',
            self::Cosmetics => 'Cosmetics shop',
            self::Electronics => 'Electronics store',
            self::Pharmacy => 'Pharmacy',
            self::Stationery => 'Stationery shop',
            self::Hardware => 'Hardware store',
            self::FruitVegetable => 'Fruit & vegetable shop',
            self::MobileAccessories => 'Mobile accessories shop',
            self::General => 'General store',
        };
    }

    public function labelBn(): string
    {
        return match ($this) {
            self::Grocery => 'মুদি দোকান',
            self::SuperShop => 'সুপার শপ',
            self::Clothing => 'কাপড়ের দোকান',
            self::Cosmetics => 'কসমেটিকস',
            self::Electronics => 'ইলেকট্রনিক্স',
            self::Pharmacy => 'ফার্মেসি',
            self::Stationery => 'স্টেশনারি',
            self::Hardware => 'হার্ডওয়্যার',
            self::FruitVegetable => 'ফল ও সবজি',
            self::MobileAccessories => 'মোবাইল এক্সেসরিজ',
            self::General => 'জেনারেল স্টোর',
        };
    }
}
