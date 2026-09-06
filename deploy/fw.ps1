# Deploy built firmware to the public site for OTA pulls.
# Usage: powershell -File fw.ps1 [main_controller]
param(
    [string]$Project = "main_controller"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$siteDir = Join-Path $PSScriptRoot "site"
$fwDir = Join-Path $siteDir "fw"

$srcBin = Join-Path $root "firmware\$Project\.pio\build\esp32-c3\firmware.bin"
if (-not (Test-Path -LiteralPath $srcBin)) {
    Write-Error "firmware.bin not found: $srcBin (run PlatformIO build first)"
}

New-Item -ItemType Directory -Path $fwDir -Force | Out-Null
Copy-Item -LiteralPath $srcBin -Destination (Join-Path $fwDir "main.bin") -Force

& scp -i "$env:USERPROFILE\.ssh\lumira_vps" -P 22 -o StrictHostKeyChecking=no `
    (Join-Path $fwDir "main.bin") root@2.26.98.234:/var/www/iot-site/fw/main.bin

Write-Host "OTA firmware deployed to https://spe4naz.online/fw/main.bin"