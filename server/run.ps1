# Restart the Share List relay server.
# Stops any process already listening on the HTTP/HTTPS ports, then starts fresh.

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

function Read-EnvFile {
    param([string]$Path)
    $values = @{}
    if (-not (Test-Path $Path)) { return $values }
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        $eq = $line.IndexOf('=')
        if ($eq -le 0) { return }
        $key = $line.Substring(0, $eq).Trim()
        $value = $line.Substring($eq + 1).Trim().Trim('"').Trim("'")
        $values[$key] = $value
    }
    return $values
}

$envValues = Read-EnvFile (Join-Path $ScriptDir '.env')
if (-not $env:PORT -and $envValues.ContainsKey('PORT')) { $env:PORT = $envValues['PORT'] }
if (-not $env:HTTPS_PORT -and $envValues.ContainsKey('HTTPS_PORT')) {
    $env:HTTPS_PORT = $envValues['HTTPS_PORT']
}

$Port = if ($env:PORT) { [int]$env:PORT } else { 3000 }
$HttpsPort = if ($env:HTTPS_PORT) { [int]$env:HTTPS_PORT } else { 3443 }
$PortsToFree = @($Port, $HttpsPort) | Select-Object -Unique

function Get-ListenersOnPort {
    param([int]$PortNumber)

    $connections = Get-NetTCPConnection -LocalPort $PortNumber -State Listen -ErrorAction SilentlyContinue
    if (-not $connections) {
        return @()
    }

    $connections |
        Select-Object -ExpandProperty OwningProcess -Unique |
        Where-Object { $_ -gt 0 }
}

foreach ($portNumber in $PortsToFree) {
    Write-Host "Checking for existing server on port $portNumber..."
    $pids = @(Get-ListenersOnPort -PortNumber $portNumber)
    if ($pids.Count -eq 0) {
        Write-Host "No existing instance on $portNumber."
        continue
    }

    foreach ($processId in $pids) {
        $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
        $name = if ($proc) { $proc.ProcessName } else { 'unknown' }
        Write-Host "Stopping PID $processId ($name) on port $portNumber..."
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }

    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        if ((Get-ListenersOnPort -PortNumber $portNumber).Count -eq 0) {
            break
        }
        Start-Sleep -Milliseconds 200
    }

    if ((Get-ListenersOnPort -PortNumber $portNumber).Count -gt 0) {
        Write-Error "Port $portNumber is still in use after attempting to stop existing processes."
        exit 1
    }

    Write-Host "Port $portNumber freed."
}

# Use the OS trust store so outbound HTTPS works behind corporate TLS inspection.
if (-not ($env:NODE_OPTIONS -match '(^|\s)--use-system-ca(\s|$)')) {
    $env:NODE_OPTIONS = if ($env:NODE_OPTIONS) {
        "$($env:NODE_OPTIONS.TrimEnd()) --use-system-ca"
    } else {
        '--use-system-ca'
    }
}

Write-Host "Starting Share List server (HTTP :$Port, HTTPS :$HttpsPort)..."
npm run dev
