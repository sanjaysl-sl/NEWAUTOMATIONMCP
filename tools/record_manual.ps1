<#
.SYNOPSIS
  Records manual taps/swipes on the phone (touch events) + a screenshot after each step.
  Output: recordings\<case>\steps.log and step-NN.png. Claude converts it to a Maestro flow
  (element IDs are resolved from the screenshots + app hierarchy afterwards, because
  uiautomator dump fails while FRND screens animate).
  Stop: create recordings\<case>\STOP  (or Ctrl+C).
.EXAMPLE
  .\tools\record_manual.ps1 -Case 01_frnd_c_tab -Device 77478578
#>
param(
    [Parameter(Mandatory)][string]$Case,
    [string]$Device = "77478578",
    [string]$Touch = "/dev/input/event6",   # Redmi A4 touchscreen (fts_ts), coords = screen pixels
    [int]$NavBarTop = 1546                  # y below this = 3-button nav bar
)
$ErrorActionPreference = "Continue"
$out = Join-Path (Split-Path $PSScriptRoot) "recordings\$Case"
New-Item -ItemType Directory -Force $out | Out-Null
Remove-Item "$out\STOP" -ErrorAction SilentlyContinue
$log = Join-Path $out "steps.log"
"# case=$Case device=$Device started=$(Get-Date -Format s)" | Set-Content $log -Encoding utf8

function Save-Screenshot([string]$name) {
    & adb.exe -s $Device shell screencap -p /data/local/tmp/rec.png 2>$null
    & adb.exe -s $Device pull /data/local/tmp/rec.png (Join-Path $out $name) 2>$null | Out-Null
}
Save-Screenshot "step-00-start.png"

# -tt forces a pty so getevent output is line-buffered (arrives per event, not in batches)
$psi = New-Object Diagnostics.ProcessStartInfo "adb.exe", "-s $Device shell getevent -lt $Touch"
$psi.RedirectStandardOutput = $true; $psi.RedirectStandardInput = $true; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$proc = [Diagnostics.Process]::Start($psi)
Write-Host "Recording '$Case' - use the phone now. To stop: create $out\STOP" -ForegroundColor Green

$x = 0; $y = 0; $sx = -1; $sy = -1; $t0 = 0.0; $tLast = 0.0; $step = 0; $down = $false
while (-not (Test-Path "$out\STOP")) {
    $task = $proc.StandardOutput.ReadLineAsync()
    while (-not $task.Wait(400)) { if (Test-Path "$out\STOP") { break } }
    if (-not $task.IsCompleted) { break }
    $line = $task.Result; if ($null -eq $line) { break }
    $ts = if ($line -match '^\[\s*([\d.]+)\]') { [double]$Matches[1] } else { $tLast }
    $tLast = $ts
    if ($line -match 'ABS_MT_POSITION_X\s+([0-9a-f]+)') { $x = [Convert]::ToInt32($Matches[1], 16); if ($down -and $sx -lt 0) { $sx = $x } }
    elseif ($line -match 'ABS_MT_POSITION_Y\s+([0-9a-f]+)') { $y = [Convert]::ToInt32($Matches[1], 16); if ($down -and $sy -lt 0) { $sy = $y } }
    elseif ($line -match 'BTN_TOUCH\s+DOWN') { $down = $true; $sx = -1; $sy = -1; $t0 = $ts }
    elseif ($line -match 'BTN_TOUCH\s+UP') {
        $down = $false
        if ($sx -lt 0) { $sx = $x }; if ($sy -lt 0) { $sy = $y }
        $ms = [int](($ts - $t0) * 1000)
        $dist = [math]::Sqrt([math]::Pow($x - $sx, 2) + [math]::Pow($y - $sy, 2))
        $kind = if ($dist -gt 40) { "swipe" } elseif ($ms -gt 600) { "longpress" } else { "tap" }
        $nav = ""
        if ($sy -gt $NavBarTop) { $nav = if ($sx -gt 440) { "BACK" } elseif ($sx -gt 280) { "HOME" } else { "RECENT_APPS" } }
        $step++
        $entry = "step=$step t=$([math]::Round($t0,2)) kind=$kind from=($sx,$sy) to=($x,$y) ms=$ms nav=$nav"
        Add-Content $log $entry -Encoding utf8
        Write-Host $entry
        Start-Sleep -Milliseconds 900
        Save-Screenshot ("step-{0:D2}.png" -f $step)
    }
}
try { $proc.Kill() } catch {}
New-Item -ItemType File -Force "$out\STOP" | Out-Null
Add-Content $log "# stopped=$(Get-Date -Format s) steps=$step" -Encoding utf8
Write-Host "Saved: $log"

