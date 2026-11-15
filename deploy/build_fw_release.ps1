param(
    [switch]$Publish
)

# Builds firmware for public OTA with NO compiled credentials:
#   * -DAERIS_NO_COMPILED_SECRETS makes config.h ignore secrets.h
#   * the device reads MQTT/API credentials from NVS (provisioned via SoftAP)
#   * every binary is scanned for the real values from secrets.h; a match
#     aborts the build before anything can be published.
#
# Usage:
#   powershell -File deploy/build_fw_release.ps1
#   powershell -File deploy/build_fw_release.ps1 -Publish
#
# Remember to bump FIRMWARE_VERSION in config.h before publishing.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "firmware\main_controller"

$pio = "C:\Users\Spe4naz\.platformio\penv\Scripts\pio.exe"
if (-not (Test-Path $pio)) {
    $cmd = Get-Command pio -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "PlatformIO not found" }
    $pio = $cmd.Source
}

$envs = @("esp32-c3", "esp32-s3", "esp32-c6")
$oldFlags = $env:PLATFORMIO_BUILD_FLAGS
$env:PLATFORMIO_BUILD_FLAGS = (($oldFlags, "-DAERIS_NO_COMPILED_SECRETS") |
    Where-Object { $_ }) -join " "

try {
    foreach ($envName in $envs) {
        Write-Host "=== building $envName (no compiled secrets) ==="
        & $pio run -d $project -e $envName
        if ($LASTEXITCODE -ne 0) { throw "build $envName failed" }
    }
} finally {
    $env:PLATFORMIO_BUILD_FLAGS = $oldFlags
}

# --- leak check -----------------------------------------------------------
$secPath = Join-Path $project "include\secrets.h"
$values = @()
if (Test-Path $secPath) {
    $sec = Get-Content $secPath -Raw
    foreach ($key in @("MQTT_PASSWORD", "SIGNALING_TOKEN")) {
        $m = [regex]::Match($sec, "#define\s+$key\s+`"([^`"]*)`"")
        if ($m.Success -and $m.Groups[1].Value) { $values += $m.Groups[1].Value }
    }
}

foreach ($envName in $envs) {
    $bin = Join-Path $project ".pio\build\$envName\firmware.bin"
    if (-not (Test-Path $bin)) { throw "missing $bin" }
    $text = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($bin))
    foreach ($v in $values) {
        if ($text.Contains($v)) { throw "SECRET LEAK detected in $envName firmware.bin" }
    }
    Write-Host "OK: $envName firmware.bin contains no compiled secrets"
}

if ($Publish) {
    Write-Host "=== publishing to /fw ==="
    & (Join-Path $PSScriptRoot "fw.ps1") -Environment esp32-c3
    if ($LASTEXITCODE -ne 0) { throw "publish esp32-c3 failed" }
    & (Join-Path $PSScriptRoot "fw.ps1") -Environment esp32-s3
    if ($LASTEXITCODE -ne 0) { throw "publish esp32-s3 failed" }
    & (Join-Path $PSScriptRoot "fw.ps1") -Environment esp32-c6
    if ($LASTEXITCODE -ne 0) { throw "publish esp32-c6 failed" }
}

Write-Host "Done."
