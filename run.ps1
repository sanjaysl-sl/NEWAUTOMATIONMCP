<#
.SYNOPSIS
  Run Maestro flows against the FRND debug app, each from a freshly launched app.

.EXAMPLE
  .\run.ps1                                                      # every .yaml directly in flows\ (not subflows\)
  .\run.ps1 flows\login_or_signup_check.yaml                     # new random 78901 number -> signup
  .\run.ps1 flows\login_or_signup_check.yaml -Phone 7890131746   # existing number -> login
  .\run.ps1 flows\login_or_signup_check.yaml -SkipOnboarding     # tap "Let's Go" with adb before Maestro starts
#>
param(
    [Parameter(Position = 0)][string]$Flow = "",
    [string]$Phone = "",
    [string]$Device = "",
    [switch]$NoClear,         # don't clear app data before each flow
    [switch]$SkipOnboarding   # tap "Let's Go" via adb so Maestro starts on the phone-number screen (carousel hang workaround)
)

$ErrorActionPreference = "Continue"
$AppId = "com.dating.for.all.debug"
$maestro = if ($env:MAESTRO_BIN) { $env:MAESTRO_BIN } elseif (Test-Path "C:\maestro\maestro\bin\maestro.bat") { "C:\maestro\maestro\bin\maestro.bat" } else { "maestro" }
$devArgs = @(); if ($Device) { $devArgs = @("-s", $Device) }
function Invoke-Adb { & adb.exe @devArgs @args 2>$null }

function Wait-ForScreen([string]$pattern, [int]$seconds = 120) {
    for ($i = 0; $i -lt ($seconds / 3); $i++) {
        $xml = Invoke-Adb exec-out "rm -f /sdcard/ui.xml; uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 && cat /sdcard/ui.xml"
        if ("$xml" -match $pattern) { return $xml }
        Start-Sleep -Seconds 3
    }
    return $null
}

# Maestro uninstalls its two helper apps after every run and reinstalls them with `adb install`.
# Xiaomi/HyperOS blocks that ("INSTALL_FAILED_USER_RESTRICTED"), so install them ourselves with an
# on-device `pm install` (approved once on the phone with "Remember my choice") and pass
# --no-reinstall-driver. Works on other phones too.
$DriverDir = Join-Path $PSScriptRoot ".maestro\driver"
function Install-MaestroDriver {
    if (-not (Test-Path "$DriverDir\maestro-app.apk")) {
        $jarDir = Join-Path (Split-Path (Split-Path ((Get-Command $maestro).Source))) "lib"
        $jar = Get-ChildItem $jarDir -Filter "maestro-client*.jar" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $jar) { return $false }
        New-Item -ItemType Directory -Force $DriverDir | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($jar.FullName)
        $zip.Entries | Where-Object { $_.Name -in "maestro-app.apk", "maestro-server.apk" } |
            ForEach-Object { [IO.Compression.ZipFileExtensions]::ExtractToFile($_, (Join-Path $DriverDir $_.Name), $true) }
        $zip.Dispose()
    }
    $ok = $true
    foreach ($apk in "maestro-app.apk", "maestro-server.apk") {
        Invoke-Adb push "$DriverDir\$apk" "/data/local/tmp/$apk" | Out-Null
        # HyperOS shows an "Install via USB" confirmation for fresh installs - tap Install on it.
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $job = Start-Job -ScriptBlock { param($da, $p) & adb.exe @da shell pm install -r -t $p 2>&1 } -ArgumentList (, $devArgs), "/data/local/tmp/$apk"
            $deadline = (Get-Date).AddSeconds(25)
            while ($job.State -eq "Running" -and (Get-Date) -lt $deadline) {
                $xml = Invoke-Adb shell "uiautomator dump /data/local/tmp/ui.xml >/dev/null 2>&1; cat /data/local/tmp/ui.xml"
                if ("$xml" -match 'text="Install"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"') {
                    Invoke-Adb shell input tap ([int](([int]$Matches[1] + [int]$Matches[3]) / 2)) ([int](([int]$Matches[2] + [int]$Matches[4]) / 2)) | Out-Null
                }
            }
            $r = Receive-Job $job -Wait; Remove-Job $job
            if ("$r" -match "Success") { break }
        }
        if ("$r" -notmatch "Success") { Write-Warning "Driver install ($apk): $r  -> tap Install + 'Remember my choice' on the phone once."; $ok = $false }
    }
    return $ok
}

$flows = if ($Flow) { @($Flow) } else { Get-ChildItem -Path "$PSScriptRoot\flows" -Filter *.yaml -File | ForEach-Object { $_.FullName } }

# Hide system "X keeps stopping" dialogs (emulator Play services crash-loops and steals focus)
Invoke-Adb shell settings put global hide_error_dialogs 1 | Out-Null

$RunDir = Join-Path $PSScriptRoot ("reports\" + (Get-Date -Format "yyyy-MM-dd_HHmmss"))
New-Item -ItemType Directory -Force $RunDir | Out-Null
$results = @()
foreach ($f in $flows) {
    Write-Host "`n=== $f ===" -ForegroundColor Cyan
    # Fresh app start - done here instead of Maestro launchApp (hangs on some devices)
    Invoke-Adb shell am force-stop $AppId | Out-Null
    if (-not $NoClear) { Invoke-Adb shell pm clear $AppId | Out-Null }
    # Pre-grant runtime permissions so the Allow dialogs never appear (faster, no popups over screens)
    foreach ($perm in "POST_NOTIFICATIONS", "ACCESS_FINE_LOCATION", "ACCESS_COARSE_LOCATION", "RECORD_AUDIO", "CAMERA",
                      "READ_MEDIA_IMAGES", "READ_MEDIA_VIDEO", "READ_MEDIA_VISUAL_USER_SELECTED", "READ_CONTACTS",
                      "READ_PHONE_STATE", "BLUETOOTH_CONNECT", "READ_EXTERNAL_STORAGE") {
        Invoke-Adb shell pm grant $AppId "android.permission.$perm" | Out-Null
    }
    Invoke-Adb shell monkey -p $AppId -c android.intent.category.LAUNCHER 1 | Out-Null
    Start-Sleep -Seconds 3

    if ($SkipOnboarding) {
        $xml = Wait-ForScreen 'id/join"'
        if ($xml -and ("$xml" -match 'resource-id="com.dating.for.all.debug:id/join"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')) {
            $x = [int](([int]$Matches[1] + [int]$Matches[3]) / 2); $y = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
            Invoke-Adb shell input tap $x $y | Out-Null
            Write-Host "Tapped Let's Go"
        } else { Write-Warning "Let's Go not found; continuing anyway." }
    }

    $maestroArgs = @("test")
    if (Install-MaestroDriver) { $maestroArgs += "--no-reinstall-driver" }
    if ($Device) { $maestroArgs += @("--device", $Device) }
    if ($Phone) { $maestroArgs += @("-e", "PHONE=$Phone") }
    # Save an HTML report + all artifacts (screenshots, recording, logs) under reports\<run>\<flow>\
    $name = [IO.Path]::GetFileNameWithoutExtension($f)
    $outDir = Join-Path $RunDir $name
    New-Item -ItemType Directory -Force $outDir | Out-Null
    $maestroArgs += @("--format", "HTML-DETAILED", "--output", (Join-Path $outDir "report.html"), "--test-output-dir", $outDir)
    $maestroArgs += $f
    & $maestro @maestroArgs
    $results += [pscustomobject]@{ Flow = (Split-Path $f -Leaf); Result = $(if ($LASTEXITCODE -eq 0) { "PASS" } else { "FAIL" }) }
}

Write-Host "`n===== Summary =====" -ForegroundColor Cyan
$results | Format-Table -AutoSize | Out-String | Write-Host
$results | Export-Csv -NoTypeInformation (Join-Path $RunDir "summary.csv")
Write-Host "Reports: $RunDir"
if ($results.Result -contains "FAIL") { exit 1 } else { exit 0 }
