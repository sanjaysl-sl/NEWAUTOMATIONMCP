<#
.SYNOPSIS
  New-male banner check on both paths: 1) signup with a new 78901 number, 2) sign-in with that same number.
.EXAMPLE
  .\tools\run_new_male_banner.ps1 -Device 77478578
#>
param([string]$Device = "77478578")
$root = Split-Path $PSScriptRoot
$flow = "flows\new_male_banner.yaml"
$phone = "78901" + (Get-Random -Minimum 10000 -Maximum 99999)
Push-Location $root
try {
    Write-Host "1/2 SIGNUP with new number $phone" -ForegroundColor Cyan
    & "$root\run.ps1" $flow -Device $Device -Phone $phone
    $signup = $LASTEXITCODE
    Write-Host "2/2 SIGN-IN with $phone" -ForegroundColor Cyan
    & "$root\run.ps1" $flow -Device $Device -Phone $phone
    $signin = $LASTEXITCODE
    Write-Host ("Signup: {0}   Sign-in: {1}   (number {2})" -f $(if ($signup -eq 0) { "PASS" } else { "FAIL" }), $(if ($signin -eq 0) { "PASS" } else { "FAIL" }), $phone)
    exit [int]($signup -ne 0 -or $signin -ne 0)
} finally { Pop-Location }
