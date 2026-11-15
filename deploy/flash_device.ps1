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

$writeCmd = if ($esptoolMajor -ge 5) { "write-flash" } else { "write_flash" }
$eraseCmd = if ($esptoolMajor -ge 5) { "erase-region" } else { "erase_region" }
$noProgress = if ($esptoolMajor -ge 5) { @("--no-progress") } else { @() }
$flashSizeArg = if ($esptoolMajor -ge 5) { "--flash-size" } else { "--flash_size" }

# The merged factory image is padded with 0xFF in every gap, so writing it at
# 0x0 replaces the NVS partition (0x9000) and wipes Wi-Fi/MQTT credentials.
# That is why a normal flash writes the segments one by one instead; the
# factory image is only used together with --erase-all, where the wipe is the
# point.
$segments = @(
    @{ Offset = "0x0";     Path = Join-Path $project ".pio\build\$Environment\bootloader.bin" },
    @{ Offset = "0x8000";  Path = Join-Path $project ".pio\build\$Environment\partitions.bin" },
    @{ Offset = "0x10000"; Path = Join-Path $project ".pio\build\$Environment\firmware.bin" }
)

if ($EraseAll -or $esptoolMajor -lt 5) {
    if ($EraseAll) {
        $flashArgs = @($writeCmd) + $noProgress + @($flashSizeArg, $flashSize,
            "--erase-all", "0x0", $factory)
    } else {
        $flashArgs = @($writeCmd, $flashSizeArg, $flashSize, "0x0", $factory)
    }
    Write-Host "Flashing $Environment via $Port (esptool $esptoolMajor.x, $flashSize, full factory image)"
} else {
    $missing = $segments | Where-Object { -not (Test-Path $_.Path) }
    if ($missing) { throw "missing build artifact: $($missing[0].Path)" }
    $flashArgs = @($writeCmd) + $noProgress + @($flashSizeArg, $flashSize) +
        @($segments | ForEach-Object { $_.Offset; $_.Path })
    Write-Host "Flashing $Environment via $Port (esptool $esptoolMajor.x, $flashSize, NVS preserved)"
}

if (-not $EraseAll -and $esptoolMajor -ge 5) {
    # Invalidate the OTA selector so the freshly written app0 is booted even if
    # an older update left app1 marked as the active slot.
    & $python $esptool --port $Port --chip $chip $eraseCmd 0xe000 0x2000
    if ($LASTEXITCODE -ne 0) { throw "erase of otadata failed (exit $LASTEXITCODE)" }
}

& $python $esptool --port $Port --chip $chip -b 460800 @flashArgs
if ($LASTEXITCODE -ne 0) { throw "flash failed (exit $LASTEXITCODE)" }

Write-Host ""
Write-Host "Flash done. Open the app -> Настройка -> Подключиться:"
Write-Host "  the port answers CMD:info even in Aeris-Setup provisioning mode."
Write-Host "After Wi-Fi is configured the log shows:"
Write-Host "  MQTT: Connected to spe4naz.online:8883"
