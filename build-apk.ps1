# Build the Share List Android APK (Flutter).
# - Bumps version to 0.0.<build> each run (major.minor fixed at 0.0)
# - Copies APK(s) to <repo>/build/

param(
    [ValidateSet('release', 'debug', 'profile')]
    [string]$Mode = 'release',

    # Build one APK per ABI (smaller installs) instead of a fat APK.
    [switch]$SplitPerAbi
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$MobileDir = Join-Path $RepoRoot 'apps\mobile'
$PubspecPath = Join-Path $MobileDir 'pubspec.yaml'
$BuildNumberFile = Join-Path $RepoRoot 'BUILD_NUMBER'
$OutDir = Join-Path $RepoRoot 'build'

if (-not (Test-Path $MobileDir)) {
    Write-Error "Mobile app not found at $MobileDir"
    exit 1
}

if (-not (Test-Path $PubspecPath)) {
    Write-Error "pubspec.yaml not found at $PubspecPath"
    exit 1
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "flutter is not on PATH. Install Flutter and ensure it is available in this shell."
    exit 1
}

# --- Bump build number: versionName 0.0.N, versionCode N ---
$buildNumber = 0
if (Test-Path $BuildNumberFile) {
    $raw = (Get-Content -Path $BuildNumberFile -Raw).Trim()
    if ($raw -match '^\d+$') {
        $buildNumber = [int]$raw
    }
}
$buildNumber++
$versionName = "0.0.$buildNumber"
$versionLine = "version: $versionName+$buildNumber"

$pubspec = Get-Content -Path $PubspecPath -Raw
if ($pubspec -notmatch '(?m)^version:\s*.+$') {
    Write-Error "Could not find a version: line in $PubspecPath"
    exit 1
}
$pubspec = [regex]::Replace($pubspec, '(?m)^version:\s*.+$', $versionLine)
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($PubspecPath, $pubspec, $utf8NoBom)
[System.IO.File]::WriteAllText($BuildNumberFile, "$buildNumber", $utf8NoBom)

Write-Host "Version set to $versionName (build $buildNumber)"

Set-Location $MobileDir

$AndroidDir = Join-Path $MobileDir 'android'
$TrustStore = Join-Path $AndroidDir '.certs\avg-truststore.jks'
if (-not (Test-Path $TrustStore)) {
    Write-Host "Java trust store missing (needed for AVG HTTPS scanning). Creating it..."
    & (Join-Path $AndroidDir 'setup-java-trust.ps1')
}
$env:JAVA_TOOL_OPTIONS = "-Djavax.net.ssl.trustStore=$TrustStore -Djavax.net.ssl.trustStorePassword=changeit"

Write-Host "Resolving Flutter dependencies..."
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter pub get failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

$buildArgs = @('build', 'apk', "--$Mode")
if ($SplitPerAbi) {
    $buildArgs += '--split-per-abi'
}

Write-Host "Building $Mode APK ($versionName)..."
Write-Host "Server defaults: see apps/mobile/lib/config/server_config.dart"
flutter @buildArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter build apk failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

$apkDir = Join-Path $MobileDir 'build\app\outputs\flutter-apk'
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

$copied = @()
Get-ChildItem -Path $apkDir -Filter '*.apk' -ErrorAction Stop | ForEach-Object {
    $suffix = ''
    if ($_.BaseName -match '-(armeabi-v7a|arm64-v8a|x86_64)$') {
        $suffix = "-$($Matches[1])"
    }
    elseif ($_.Name -ne "app-$Mode.apk" -and $_.BaseName -ne "app-$Mode") {
        # Keep any unexpected flutter output name distinguishable.
        $suffix = "-$($_.BaseName)"
    }

    $destName = "share-list-$versionName-$Mode$suffix.apk"
    $destPath = Join-Path $OutDir $destName
    Copy-Item -Path $_.FullName -Destination $destPath -Force
    $copied += $destPath
}

Write-Host ""
Write-Host "APK build complete."
Write-Host "Version: $versionName+$buildNumber"
Write-Host "Copied to: $OutDir"
foreach ($path in $copied) {
    Write-Host "  $path"
}
