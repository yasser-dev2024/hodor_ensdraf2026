$ErrorActionPreference = "Stop"
$sourceRoot = Split-Path -Parent $PSScriptRoot
$sourceTruststore = Join-Path $sourceRoot "android\windows-cacerts"
$sourceKeyProperties = Join-Path $sourceRoot "android\key.properties"
$sourceKeystore = Join-Path $sourceRoot "android\release-key.jks"
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "morning-attendance-release-workspace"
$pubspec = Get-Content -LiteralPath (Join-Path $sourceRoot "pubspec.yaml") -Raw -Encoding UTF8
$versionMatch = [Regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$')
if (-not $versionMatch.Success) { throw "Could not read the app version from pubspec.yaml." }
$versionName = $versionMatch.Groups[1].Value
$versionCode = $versionMatch.Groups[2].Value
$releaseTarget = Join-Path $sourceRoot "releases\morning-attendance-v$versionName.apk"

if (-not (Test-Path -LiteralPath $sourceTruststore)) {
    throw "Run tool/create_gradle_truststore.ps1 before building on this machine."
}
if (-not (Test-Path -LiteralPath $sourceKeyProperties) -or
    -not (Test-Path -LiteralPath $sourceKeystore)) {
    throw "Release signing files are required on this machine."
}

$resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
if (-not $resolvedTemporaryRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($resolvedTemporaryRoot) -ne "morning-attendance-release-workspace") {
    throw "Unexpected release workspace path."
}
New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null

# Mirror source into a stable ASCII path. Build caches stay in this workspace,
# while private signing material and issued activation keys are excluded.
& robocopy.exe $sourceRoot $temporaryRoot /MIR /R:2 /W:1 `
    /XD .git build .dart_tool .gradle releases issued_activation_keys `
    /XF .activation_private_key key.properties release-key.jks windows-cacerts `
    /NFL /NDL /NJH /NJS /NP | Out-Null
$copyExitCode = $LASTEXITCODE
if ($copyExitCode -gt 7) {
    throw "Could not synchronize the ASCII release workspace (robocopy exit $copyExitCode)."
}

$temporaryKeyProperties = Join-Path $temporaryRoot "android\key.properties"
$temporaryKeystore = Join-Path $temporaryRoot "android\release-key.jks"
$temporaryTruststore = Join-Path $temporaryRoot "android\windows-cacerts"
try {
    Copy-Item -LiteralPath $sourceKeyProperties -Destination $temporaryKeyProperties -Force
    Copy-Item -LiteralPath $sourceKeystore -Destination $temporaryKeystore -Force
    Copy-Item -LiteralPath $sourceTruststore -Destination $temporaryTruststore -Force

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
    # The workspace cache is intentionally retained, but private signing files
    # never remain in it between builds.
    [IO.File]::Delete($temporaryKeyProperties)
    [IO.File]::Delete($temporaryKeystore)
    [IO.File]::Delete($temporaryTruststore)
}
