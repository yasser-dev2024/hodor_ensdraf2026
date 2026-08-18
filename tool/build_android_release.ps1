$ErrorActionPreference = "Stop"
$sourceRoot = Split-Path -Parent $PSScriptRoot
$sourceTruststore = Join-Path $sourceRoot "android\windows-cacerts"
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("attendance-release-build-" + [Guid]::NewGuid().ToString("N"))
$releaseTarget = Join-Path $sourceRoot "releases\morning-attendance-v1.0.0.apk"

if (-not (Test-Path -LiteralPath $sourceTruststore)) {
    throw "Run tool/create_gradle_truststore.ps1 before building on this machine."
}

New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
try {
    # Flutter's Windows AOT tools cannot write through a source path containing
    # non-ASCII characters, so compile an isolated copy in the system temp path.
    Get-ChildItem -LiteralPath $sourceRoot -Force |
        Where-Object { $_.Name -notin @("build", ".dart_tool", ".git", "releases", "tool") } |
        Copy-Item -Destination $temporaryRoot -Recurse -Force

    # Copy build utilities but never copy the private activation signer or
    # previously issued keys into a disposable build directory.
    $temporaryTool = Join-Path $temporaryRoot "tool"
    New-Item -ItemType Directory -Path $temporaryTool | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $sourceRoot "tool") -Force |
        Where-Object { $_.Name -notin @(".activation_private_key", "issued_activation_keys") } |
        Copy-Item -Destination $temporaryTool -Recurse -Force

    $temporaryTruststore = Join-Path $temporaryRoot "android\windows-cacerts"
    $env:JAVA_HOME = "C:\Program Files\Android\Android Studio1\jbr"
    $env:PATH = (Join-Path $env:JAVA_HOME "bin") + ";" + $env:PATH
    $env:GRADLE_OPTS = "-Djavax.net.ssl.trustStore=$temporaryTruststore -Djavax.net.ssl.trustStorePassword=changeit -Djavax.net.ssl.trustStoreType=JKS"

    Push-Location $temporaryRoot
    try {
        & flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed with exit code $LASTEXITCODE" }
        & flutter build apk --release
        if ($LASTEXITCODE -ne 0) { throw "Flutter Android build failed with exit code $LASTEXITCODE" }
    }
    finally {
        Pop-Location
    }

    $builtApk = Join-Path $temporaryRoot "build\app\outputs\flutter-apk\app-release.apk"
    if (-not (Test-Path -LiteralPath $builtApk)) { throw "The release APK was not produced." }
    Copy-Item -LiteralPath $builtApk -Destination $releaseTarget -Force
    Write-Output "Release APK copied to $releaseTarget"
}
finally {
    $resolvedTemp = [IO.Path]::GetFullPath($temporaryRoot)
    $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemp).StartsWith("attendance-release-build-") -and
        (Test-Path -LiteralPath $resolvedTemp)) {
        try {
            Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
        }
        catch {
            # Gradle or lint can briefly retain a file handle after the build.
            # Cleanup must never hide the actual build result.
            Write-Warning "Temporary build directory could not be removed yet: $resolvedTemp"
        }
    }
}
