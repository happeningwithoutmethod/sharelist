# Generate a self-signed TLS cert for local HTTPS (dev only).
# Output: server/certs/cert.pem + server/certs/key.pem

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CertsDir = Join-Path $ScriptDir 'certs'
$CertPath = Join-Path $CertsDir 'cert.pem'
$KeyPath = Join-Path $CertsDir 'key.pem'

# Prefer HOSTNAME from .env when present.
$Hostname = 'localhost'
$EnvFile = Join-Path $ScriptDir '.env'
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -match '^HOSTNAME=(.+)$') {
            $Hostname = $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
}

New-Item -ItemType Directory -Force -Path $CertsDir | Out-Null

if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
    Write-Error "openssl is required. Install OpenSSL and ensure it is on PATH."
    exit 1
}

Write-Host "Generating self-signed cert for $Hostname ..."
& openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes `
    -keyout $KeyPath `
    -out $CertPath `
    -subj "/CN=$Hostname" `
    -addext "subjectAltName=DNS:$Hostname,DNS:localhost,IP:127.0.0.1"

if ($LASTEXITCODE -ne 0) {
    Write-Error "openssl failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "Wrote:"
Write-Host "  $CertPath"
Write-Host "  $KeyPath"
Write-Host "Set ENABLE_HTTPS=true in .env (already the default in .env.example)."
