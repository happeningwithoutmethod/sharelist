# Copy the latest Share List release APK to the relay host (served at /apk).
#
# Expects APKs from build-apk.ps1 under <repo>/build/:
#   share-list-0.0.N-release.apk
#
# Usage:
#   .\copy-apk.ps1
#   .\copy-apk.ps1 -RemoteHost 192.168.1.222 -User hwm

param(
    [string]$RemoteHost = '192.168.1.222',
    [string]$User = 'hwm',
    [string]$RemotePath = '~/dev/sharelist/server/public/apk/sharelist-latest.apk',
    # Prefer fat APK; set to include ABI-split builds when choosing "latest"
    [switch]$AllowSplitAbi
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BuildDir = Join-Path $RepoRoot 'build'

if (-not (Test-Path $BuildDir)) {
    Write-Error "Build folder not found at $BuildDir. Run .\build-apk.ps1 first."
    exit 1
}

if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
    Write-Error "scp is not on PATH (OpenSSH client required)."
    exit 1
}

$candidates = Get-ChildItem -Path $BuildDir -Filter 'share-list-*-release*.apk' -File -ErrorAction SilentlyContinue
if (-not $candidates -or $candidates.Count -eq 0) {
    Write-Error "No release APKs found in $BuildDir. Run .\build-apk.ps1 first."
    exit 1
}

if (-not $AllowSplitAbi) {
    # Prefer the fat APK: share-list-0.0.N-release.apk (no ABI suffix).
    $fat = $candidates | Where-Object {
        $_.Name -match '^share-list-\d+\.\d+\.\d+-release\.apk$'
    }
    if ($fat) {
        $candidates = $fat
    }
}

$latest = $candidates |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $latest) {
    Write-Error "Could not determine the latest APK in $BuildDir."
    exit 1
}

$destination = "${User}@${RemoteHost}:${RemotePath}"
Write-Host "Uploading:"
Write-Host "  $($latest.FullName)"
Write-Host "  ($([math]::Round($latest.Length / 1MB, 2)) MB, $($latest.LastWriteTime))"
Write-Host "To:"
Write-Host "  $destination"
Write-Host ""

scp $latest.FullName $destination
if ($LASTEXITCODE -ne 0) {
    Write-Error "scp failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Done. APK is live at https://sharelist.servehttp.com/apk (nginx bind-mount)."
