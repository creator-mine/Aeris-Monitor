param(
    [switch]$SkipBuild
)

# Builds the Aeris Monitor Windows desktop app (release) and packages it with
# Inno Setup 6 (deploy/installer/windesktop.iss). The installer lands in
# deploy/installer/output/aeris_setup_<version>.exe.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root "mobile_app"

# --- Locate Flutter -------------------------------------------------------
$flutter = "C:\flutter\flutter\bin\flutter.bat"
if (-not (Test-Path $flutter)) {
    $cmd = Get-Command flutter -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "Flutter not found (expected C:\flutter or PATH)" }
    $flutter = $cmd.Source
}

if (-not $SkipBuild) {
    Push-Location $app
    try {
        & $flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }
    } finally {
        Pop-Location
    }
}

$exe = Join-Path $app "build\windows\x64\runner\Release\aeris.exe"
if (-not (Test-Path $exe)) { throw "Windows build not found: $exe" }

# --- Version from pubspec -------------------------------------------------
$versionLine = Select-String -Path (Join-Path $app "pubspec.yaml") -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)' |
    Select-Object -First 1
if (-not $versionLine) { throw "Cannot read version from pubspec.yaml" }
$version = $versionLine.Matches[0].Groups[1].Value

# --- Locate Inno Setup ----------------------------------------------------
$iscc = @(
    (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
    throw "Inno Setup 6 not found. Install it or run with -SkipBuild and compile deploy/installer/windesktop.iss manually."
}

$iss = Join-Path $PSScriptRoot "installer\windesktop.iss"
& $iscc "/DAppVersion=$version" $iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed" }

$setup = Join-Path $PSScriptRoot "installer\output\aeris_setup_$version.exe"
if (-not (Test-Path $setup)) { throw "Installer not found: $setup" }

Write-Host "Windows installer -> $setup"
Write-Host ("Size:   {0} bytes" -f (Get-Item $setup).Length)
Write-Host ("SHA256: {0}" -f (Get-FileHash $setup -Algorithm SHA256).Hash.ToLower())
