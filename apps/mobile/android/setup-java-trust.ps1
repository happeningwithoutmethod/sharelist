# Build a Java trust store that includes AVG Web/Mail Shield's HTTPS-scan root.
# AVG (and similar AV) intercepts TLS; Java does not use the Windows cert store by default,
# which breaks Gradle downloads (PKIX path building failed).
#
# Run from anywhere:
#   powershell -File apps/mobile/android/setup-java-trust.ps1

$ErrorActionPreference = 'Stop'

$AndroidDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CertsDir = Join-Path $AndroidDir '.certs'
$TrustStore = Join-Path $CertsDir 'avg-truststore.jks'
$RootCer = Join-Path $CertsDir 'avg-root.cer'

function Find-JbrHome {
    $flutterJdk = (flutter config --list 2>$null | Select-String 'jdk-dir') 
    $candidates = @(
        'C:\Program Files\Android\Android Studio1\jbr',
        'C:\Program Files\Android\Android Studio\jbr',
        "$env:LOCALAPPDATA\Programs\Android\Android Studio\jbr",
        $env:JAVA_HOME
    ) | Where-Object { $_ -and (Test-Path $_) }
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c 'bin\keytool.exe')) { return $c }
        if (Test-Path (Join-Path $c 'keytool.exe')) { return (Split-Path (Split-Path $c)) }
    }
    throw 'Could not find Android Studio JBR / JDK with keytool.'
}

Write-Host "Capturing AVG HTTPS-scan certificate from plugins.gradle.org..."
New-Item -ItemType Directory -Force -Path $CertsDir | Out-Null

$tcp = New-Object System.Net.Sockets.TcpClient('plugins.gradle.org', 443)
$ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, { $true })
$ssl.AuthenticateAsClient('plugins.gradle.org')
$leaf = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $ssl.RemoteCertificate
$chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
$chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
[void]$chain.Build($leaf)

$root = $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate
[IO.File]::WriteAllBytes($RootCer, $root.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
$ssl.Close(); $tcp.Close()
Write-Host "Root: $($root.Subject)"

$jbr = Find-JbrHome
Write-Host "Using JDK: $jbr"
$cacerts = Join-Path $jbr 'lib\security\cacerts'
if (-not (Test-Path $cacerts)) {
    throw "cacerts not found at $cacerts"
}

Copy-Item $cacerts $TrustStore -Force
$keytool = Join-Path $jbr 'bin\keytool.exe'
& $keytool -importcert -noprompt -alias avg-web-mail-shield-root `
    -file $RootCer -keystore $TrustStore -storepass changeit

Write-Host ""
Write-Host "Trust store ready: $TrustStore"
Write-Host "gradle.properties already points Gradle at .certs/avg-truststore.jks"
Write-Host "For the Gradle wrapper itself, also set:"
Write-Host '  $env:JAVA_TOOL_OPTIONS = "-Djavax.net.ssl.trustStore=$TrustStore -Djavax.net.ssl.trustStorePassword=changeit"'
