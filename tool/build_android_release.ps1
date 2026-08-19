$ErrorActionPreference = "Stop"
$sourceRoot = Split-Path -Parent $PSScriptRoot
$sourceTruststore = Join-Path $sourceRoot "android\windows-cacerts"
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("attendance-release-build-" + [Guid]::NewGuid().ToString("N"))
$pubspec = Get-Content -LiteralPath (Join-Path $sourceRoot "pubspec.yaml") -Raw -Encoding UTF8
$versionMatch = [Regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$')
if (-not $versionMatch.Success) { throw "Could not read the app version from pubspec.yaml." }
$versionName = $versionMatch.Groups[1].Value
$versionCode = $versionMatch.Groups[2].Value
$releaseTarget = Join-Path $sourceRoot "releases\morning-attendance-v$versionName.apk"

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
    # Release builds on this machine are intentionally offline. Pub may only
    # use its local cache, and Java/Gradle are pointed at a closed local proxy
    # so an unexpected repository or redirect can never reach the internet.
    $env:HTTP_PROXY = "http://127.0.0.1:9"
    $env:HTTPS_PROXY = "http://127.0.0.1:9"
    $env:NO_PROXY = "localhost,127.0.0.1"
    $env:GRADLE_OPTS = "-Djavax.net.ssl.trustStore=$temporaryTruststore -Djavax.net.ssl.trustStorePassword=changeit -Djavax.net.ssl.trustStoreType=JKS -Dorg.gradle.offline=true -Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=9 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=9"

    Push-Location $temporaryRoot
    try {
        & flutter pub get --offline
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get --offline failed with exit code $LASTEXITCODE" }
        & flutter build apk --release --no-pub
        if ($LASTEXITCODE -ne 0) { throw "Flutter Android build failed with exit code $LASTEXITCODE" }
    }
    finally {
        Pop-Location
    }

    $builtApk = Join-Path $temporaryRoot "build\app\outputs\flutter-apk\app-release.apk"
    if (-not (Test-Path -LiteralPath $builtApk)) { throw "The release APK was not produced." }
    Copy-Item -LiteralPath $builtApk -Destination $releaseTarget -Force
    $apkFile = Get-Item -LiteralPath $releaseTarget
    $apkSize = "{0:N1} MB" -f ($apkFile.Length / 1MB)
    $apkHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $releaseTarget).Hash
    $downloadPage = Join-Path $sourceRoot "index.html"
    if (Test-Path -LiteralPath $downloadPage) {
        $page = Get-Content -LiteralPath $downloadPage -Raw -Encoding UTF8
        $page = [Regex]::Replace($page, '(<dd id="apk-size">)[^<]*(</dd>)', { param($match) $match.Groups[1].Value + $apkSize + $match.Groups[2].Value })
        $page = [Regex]::Replace($page, '(<dd id="apk-sha256">)[^<]*(</dd>)', { param($match) $match.Groups[1].Value + $apkHash + $match.Groups[2].Value })
        $releaseDate = (Get-Date).ToString('yyyy-MM-dd')
        $page = [Regex]::Replace($page, '(<dd id="release-date">)[^<]*(</dd>)', { param($match) $match.Groups[1].Value + $releaseDate + $match.Groups[2].Value })
        $page = [Regex]::Replace($page, '(<dd id="app-version">)[^<]*(</dd>)', { param($match) $match.Groups[1].Value + "$versionName ($versionCode)" + $match.Groups[2].Value })
        $page = [Regex]::Replace($page, 'href="releases/morning-attendance-v[^"]+\.apk"', "href=`"releases/morning-attendance-v$versionName.apk`"")
        [IO.File]::WriteAllText($downloadPage, $page, [Text.UTF8Encoding]::new($false))
    }
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
