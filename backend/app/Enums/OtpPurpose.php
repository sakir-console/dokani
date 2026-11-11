<?php

namespace App\Enums;

enum OtpPurpose: string
{
    case ResetPassword = 'reset_password';
    case Register = 'register';
}
