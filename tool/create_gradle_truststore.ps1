param(
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectRoot "android\windows-cacerts"
}
$keytool = "C:\Program Files\Android\Android Studio1\jbr\bin\keytool.exe"
$jdkTruststore = "C:\Program Files\Android\Android Studio1\jbr\lib\security\cacerts"

if (-not (Test-Path -LiteralPath $keytool) -or -not (Test-Path -LiteralPath $jdkTruststore)) {
    throw "Android Studio JBR trust tools were not found."
}
if (-not (Test-Path -LiteralPath $OutputPath)) {
    Copy-Item -LiteralPath $jdkTruststore -Destination $OutputPath
}
$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ("gradle-roots-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null

try {
    $certificates = @(
        Get-ChildItem Cert:\CurrentUser\Root
        Get-ChildItem Cert:\LocalMachine\Root
    ) | Sort-Object Thumbprint -Unique

    $imported = 0
    foreach ($certificate in $certificates) {
        $certificatePath = Join-Path $temporaryDirectory ($certificate.Thumbprint + ".cer")
        [IO.File]::WriteAllBytes($certificatePath, $certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        & $keytool -importcert -noprompt -trustcacerts -keystore $OutputPath -storepass changeit -alias ("windows-" + $certificate.Thumbprint) -file $certificatePath 2>&1 | Out-Null
        $importExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousPreference
        if ($importExitCode -eq 0) { $imported++ }
    }
    Write-Output "Created a build-only truststore with $imported Windows root certificates."
}
finally {
    $resolvedTemp = [IO.Path]::GetFullPath($temporaryDirectory)
    $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTemp)) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}
