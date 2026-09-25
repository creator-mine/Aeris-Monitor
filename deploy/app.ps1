param(
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root "mobile_app"
$buildDir = Join-Path $app "build\web"
$remote = "root@2.26.98.234"
$remotePath = "/var/www/app"

if (-not $SkipBuild) {
    $env:Path += ";C:\flutter\flutter\bin"
    Push-Location $app
    try {
        & "C:\flutter\flutter\bin\flutter.bat" build web --release
    } finally {
        Pop-Location
    }
    if ($LASTEXITCODE -ne 0) { throw "flutter build web failed" }
}

if (-not (Test-Path -LiteralPath (Join-Path $buildDir "index.html"))) {
    throw "build/web/index.html not found; run without -SkipBuild first"
}

ssh -i "C:\Users\Spe4naz\.ssh\lumira_vps" $remote "mkdir -p $remotePath"
scp -r -i "C:\Users\Spe4naz\.ssh\lumira_vps" "${buildDir}\*" "${remote}:${remotePath}/"
ssh -i "C:\Users\Spe4naz\.ssh\lumira_vps" $remote "chown -R www-data:www-data $remotePath"
Write-Host "Deployed flutter web to https://spe4naz.online/app/"