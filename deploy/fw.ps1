# Deploy built firmware to the public site for OTA pulls.
# Generates version manifest (real version/build date/sha256) next to the bin.
#
# Per-device-type artifacts:
#   esp32-c3 -> /fw/main.bin + /fw/version.json               (legacy layout)
#   esp32-c6 -> /fw/main_esp32-c6.bin + /fw/version-esp32-c6.json
#   esp32-s3 -> /fw/main_esp32-s3.bin + /fw/version-esp32-s3.json
#
# Usage: powershell -File fw.ps1 [-Project main_controller] [-Environment esp32-c3]
param(
    [string]$Project = "main_controller",
    [string]$Environment = "esp32-c3"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$siteDir = Join-Path $PSScriptRoot "site"
$fwDir = Join-Path $siteDir "fw"
$projectDir = Join-Path $root "firmware\$Project"
$configHeader = Join-Path $projectDir "include\config.h"

$legacy = $Environment -eq "esp32-c3"
$baseName = if ($legacy) { "main" } else { "main_$Environment" }
$binName = "$baseName.bin"
$manifestName = if ($legacy) { "version.json" } else { "version-$Environment.json" }

$srcBin = Join-Path $projectDir ".pio\build\$Environment\firmware.bin"
if (-not (Test-Path -LiteralPath $srcBin)) {
    Write-Error "firmware.bin not found: $srcBin (run PlatformIO build first)"
}
if (-not (Test-Path -LiteralPath $configHeader)) {
    Write-Error "config.h not found: $configHeader (cannot read FIRMWARE_VERSION)"
}

$version = "0.0.0"
$match = Select-String -LiteralPath $configHeader -Pattern '#define\s+FIRMWARE_VERSION\s+"([^"]+)"'
if ($match -and $match.Matches.Count -gt 0) {
    $version = $match.Matches[0].Groups[1].Value
}

$bytes = [System.IO.File]::ReadAllBytes($srcBin)
$sha256 = (Get-FileHash -LiteralPath $srcBin -Algorithm SHA256).Hash.ToLowerInvariant()
$buildDate = [DateTime]::UtcNow.ToString("o")

$manifest = [ordered]@{
    version      = $version
    device_type  = $Environment
    build_date   = $buildDate
    sha256       = $sha256
    size         = $bytes.Length
    file         = $binName
}

New-Item -ItemType Directory -Path $fwDir -Force | Out-Null
Copy-Item -LiteralPath $srcBin -Destination (Join-Path $fwDir $binName) -Force
$manifestJson = $manifest | ConvertTo-Json -Compress
[System.IO.File]::WriteAllText(
    (Join-Path $fwDir $manifestName),
    $manifestJson,
    [System.Text.UTF8Encoding]::new($false)
)

& scp -i "$env:USERPROFILE\.ssh\iot_vps" -P 22 -o StrictHostKeyChecking=no `
    (Join-Path $fwDir $binName) "root@48.102.204.190:/opt/iot/deploy/docker/runtime/site/fw/$binName"
if ($LASTEXITCODE -ne 0) { throw "scp $binName failed (exit $LASTEXITCODE)" }

& scp -i "$env:USERPROFILE\.ssh\iot_vps" -P 22 -o StrictHostKeyChecking=no `
    (Join-Path $fwDir $manifestName) "root@48.102.204.190:/opt/iot/deploy/docker/runtime/site/fw/$manifestName"
if ($LASTEXITCODE -ne 0) { throw "scp $manifestName failed (exit $LASTEXITCODE)" }

Write-Host "OTA firmware v$version deployed -> https://spe4naz.online/fw/$binName"
Write-Host "Manifest -> https://spe4naz.online/fw/$manifestName (sha256 $sha256)"