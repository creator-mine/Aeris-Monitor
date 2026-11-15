param(
    [ValidateSet("esp32-c3", "esp32-c6", "esp32-s3")]
    [string]$Environment = "esp32-c3",
    [string]$Port = ""
)

# One-time USB bootstrap flash for the Aeris Monitor main controller.
#
# Why USB: devices still running the pre-migration image point at the old
# broker (2.26.98.234) and cannot receive the OTA command. Flash once over
# USB; every later update is delivered over the air.
#
# Usage:
#   powershell -File deploy/flash_device.ps1 -Environment esp32-c3
#   powershell -File deploy/flash_device.ps1 -Environment esp32-c6 -Port COM5

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "firmware\main_controller"

$pio = "C:\Users\Spe4naz\.platformio\penv\Scripts\pio.exe"
if (-not (Test-Path $pio)) {
    $cmd = Get-Command pio -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "PlatformIO not found (expected C:\Users\...\.platformio\penv\Scripts\pio.exe or PATH)" }
    $pio = $cmd.Source
}

$args = @("run", "-d", $project, "-e", $Environment, "-t", "upload")
if ($Port) { $args += @("--upload-port", $Port) }

Write-Host "Flashing $Environment from $project"
& $pio @args
if ($LASTEXITCODE -ne 0) { throw "flash failed (exit $LASTEXITCODE)" }

Write-Host ""
Write-Host "Flash done. Verify in the serial log:"
Write-Host "  MQTT: Connected to spe4naz.online:8883"
Write-Host "Then the device appears online in the panel; later updates go via OTA."
