param(
    [ValidateSet("esp32-c3", "esp32-c6", "esp32-s3")]
    [string]$Environment = "esp32-c3",
    [string]$Port = "",
    [switch]$EraseAll
)

# One-time USB bootstrap flash for the Aeris Monitor main controller.
#
# Why USB: a blank board (or one still running the pre-migration image that
# points at the old broker) cannot be reached over the air. Flash once over
# USB from offset 0x0 with the *factory* image (bootloader + partition table +
# app); every later update is delivered via OTA.
#
# Writes the factory image, so a changed flash layout (e.g. 8 MB -> 16 MB) is
# applied as well. NVS is preserved by default: Wi-Fi and MQTT credentials that
# were already provisioned survive a firmware update. Pass -EraseAll for a
# truly blank device (new board, forgotten credentials, layout change).
#
# Usage:
#   powershell -File deploy/flash_device.ps1 -Environment esp32-c6 -Port COM7
#   powershell -File deploy/flash_device.ps1 -Environment esp32-c3 -EraseAll

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "firmware\main_controller"

$chip = @{
    "esp32-c3" = "esp32c3"
    "esp32-c6" = "esp32c6"
    "esp32-s3" = "esp32s3"
}[$Environment]

$flashSize = @{
    "esp32-c3" = "4MB"
    "esp32-c6" = "16MB"
    "esp32-s3" = "16MB"
}[$Environment]

$factory = Join-Path $project ".pio\build\$Environment\firmware.factory.bin"

# --- Toolchain -------------------------------------------------------------
$coreDirs = @(
    "$env:USERPROFILE\.platformio",
    (Join-Path $root ".pio_home")
) | Where-Object { Test-Path $_ }

$esptool = $null
foreach ($dir in $coreDirs) {
    $candidate = Join-Path $dir "packages\tool-esptoolpy\esptool.py"
    if (Test-Path $candidate) { $esptool = $candidate; break }
}
if (-not $esptool) { throw "esptool.py not found (run a PlatformIO build first)" }

$python = "$env:USERPROFILE\.platformio\penv\Scripts\python.exe"
if (-not (Test-Path $python)) {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "Python not found" }
    $python = $cmd.Source
}

$pio = "$env:USERPROFILE\.platformio\penv\Scripts\pio.exe"
if (-not (Test-Path $pio)) {
    $cmd = Get-Command pio -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "PlatformIO not found" }
    $pio = $cmd.Source
}

# esptool chokes on non-UTF-8 consoles (cp1251) while drawing its progress bar.
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

# --- Build the factory image if it is missing ------------------------------
if (-not (Test-Path $factory)) {
    Write-Host "=== building $Environment (no compiled secrets) ==="
    $oldFlags = $env:PLATFORMIO_BUILD_FLAGS
    $env:PLATFORMIO_BUILD_FLAGS = (($oldFlags, "-DAERIS_NO_COMPILED_SECRETS") |
        Where-Object { $_ }) -join " "
    try {
        & $pio run -d $project -e $Environment
    } finally {
        $env:PLATFORMIO_BUILD_FLAGS = $oldFlags
    }
    if ($LASTEXITCODE -ne 0) { throw "build $Environment failed" }
    if (-not (Test-Path $factory)) { throw "missing $factory" }
}

# --- Pick a port -----------------------------------------------------------
if (-not $Port) {
    $ports = @([System.IO.Ports.SerialPort]::GetPortNames())
    $candidates = @($ports | Where-Object { $_ -ne "COM1" })
    if ($candidates.Count -eq 1) { $Port = $candidates[0] }
    elseif ($ports.Count -eq 1) { $Port = $ports[0] }
    else {
        throw "Specify -Port (available: $($ports -join ', '))"
    }
    Write-Host "Auto-selected $Port"
}

# --- esptool 4.x vs 5.x argument spelling ----------------------------------
$versionText = (& $python $esptool version 2>&1 | Out-String)
$esptoolMajor = 4
if ($versionText -match '(?m)^\s*(\d+)\.\d+') { $esptoolMajor = [int]$Matches[1] }

$eraseArgs = if ($EraseAll) { @("--erase-all") } else { @() }
if ($esptoolMajor -ge 5) {
    $flashArgs = @("write-flash", "--no-progress", "--flash-size", $flashSize) +
        $eraseArgs + @("0x0", $factory)
} else {
    $flashArgs = @("write_flash", "--flash_size", $flashSize) + $eraseArgs +
        @("0x0", $factory)
}

Write-Host "Flashing $Environment via $Port (esptool $esptoolMajor.x, $flashSize)"
& $python $esptool --port $Port --chip $chip -b 460800 @flashArgs
if ($LASTEXITCODE -ne 0) { throw "flash failed (exit $LASTEXITCODE)" }

Write-Host ""
Write-Host "Flash done. Open the app -> Настройка -> Подключиться:"
Write-Host "  the port answers CMD:info even in Aeris-Setup provisioning mode."
Write-Host "After Wi-Fi is configured the log shows:"
Write-Host "  MQTT: Connected to spe4naz.online:8883"
