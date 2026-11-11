param(
    [switch]$SkipPubGet
)

# Builds the Aeris Monitor Android APK (release, signed with
# mobile_app/android/key.properties) and copies it to deploy/installer/output.

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

# --- Locate JDK / Android SDK --------------------------------------------
if (-not $env:JAVA_HOME) {
    $jdk = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory -Filter "jdk-*" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($jdk) { $env:JAVA_HOME = $jdk.FullName }
}
if (-not $env:ANDROID_HOME) {
    $sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
    if (Test-Path $sdk) {
        $env:ANDROID_HOME = $sdk
        $env:ANDROID_SDK_ROOT = $sdk
    }
}

Push-Location $app
try {
    if (-not $SkipPubGet) {
        & $flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
    }
    & $flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed" }
} finally {
    Pop-Location
}

$src = Join-Path $app "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $src)) { throw "APK not found: $src" }

$outDir = Join-Path $PSScriptRoot "installer\output"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$dst = Join-Path $outDir "aeris-monitor-1.2.0.apk"
Copy-Item $src $dst -Force

$hash = (Get-FileHash $dst -Algorithm SHA256).Hash.ToLower()
Write-Host "APK -> $dst"
Write-Host "SHA256: $hash"
