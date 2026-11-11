<?php

namespace App\Livewire\Admin;

use App\Services\Admin\DashboardStats;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Component;

#[Layout('components.admin.layout')]
#[Title('Dashboard')]
class Dashboard extends Component
{
    public function render(DashboardStats $stats)
    {
        return view('livewire.admin.dashboard', [
            'shops' => $stats->shops(),
            'registrations' => $stats->registrations(),
            'subscriptions' => $stats->subscriptions(),
            'series' => $stats->registrationSeries(),
            'activity' => $stats->recentActivity(),
            'recentShops' => $stats->recentShops(),
        ]);
    }
}
