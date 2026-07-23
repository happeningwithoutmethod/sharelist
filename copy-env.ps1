# Copy local client/.env and server/.env to the Ubuntu relay host.
#
# Remote layout matches this repo (see docker-compose bind mounts):
#   ~/dev/sharelist/server/.env  → share-list:/app/.env
#   ~/dev/sharelist/client/.env  → share-list-client:/config/.env
#
# Usage:
#   .\copy-env.ps1
#   .\copy-env.ps1 -RemoteHost 192.168.1.222 -User hwm
#   .\copy-env.ps1 -ClientOnly
#   .\copy-env.ps1 -ServerOnly

param(
    [string]$RemoteHost = '192.168.1.222',
    [string]$User = 'hwm',
    [string]$RemoteRoot = '~/dev/sharelist',
    [switch]$ClientOnly,
    [switch]$ServerOnly
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($ClientOnly -and $ServerOnly) {
    Write-Error "Use at most one of -ClientOnly / -ServerOnly."
    exit 1
}

if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
    Write-Error "scp is not on PATH (OpenSSH client required)."
    exit 1
}

$copyClient = -not $ServerOnly
$copyServer = -not $ClientOnly

$jobs = @()
if ($copyServer) {
    $jobs += [pscustomobject]@{
        Label = 'server'
        Local = Join-Path $RepoRoot 'server\.env'
        Remote = "${RemoteRoot}/server/.env"
    }
}
if ($copyClient) {
    $jobs += [pscustomobject]@{
        Label = 'client'
        Local = Join-Path $RepoRoot 'client\.env'
        Remote = "${RemoteRoot}/client/.env"
    }
}

foreach ($job in $jobs) {
    if (-not (Test-Path -LiteralPath $job.Local -PathType Leaf)) {
        Write-Error "Missing $($job.Local). Copy from $($job.Label)/.env.example first."
        exit 1
    }
}

foreach ($job in $jobs) {
    $destination = "${User}@${RemoteHost}:$($job.Remote)"
    Write-Host "Uploading $($job.Label) .env:"
    Write-Host "  $($job.Local)"
    Write-Host "To:"
    Write-Host "  $destination"
    scp $job.Local $destination
    if ($LASTEXITCODE -ne 0) {
        Write-Error "scp failed for $($job.Label) .env (exit $LASTEXITCODE)"
        exit $LASTEXITCODE
    }
    Write-Host ""
}

Write-Host "Done. Recreate containers on the host so they reload env:"
Write-Host "  cd $($RemoteRoot)/server"
Write-Host "  docker compose up -d --force-recreate share-list share-list-client"
