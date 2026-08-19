param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId
)

$ErrorActionPreference = "Stop"
$sourceRoot = Split-Path -Parent $PSScriptRoot
$acceptancePackage = "sa.school.attendance.morning_student_attendance.debug"
$executionRoot = Join-Path ([IO.Path]::GetTempPath()) "morning-attendance-integration-workspace"

# gradlew.bat and impellerc on some Arabic Windows installations cannot build
# reliably from a non-ASCII path. Keep a stable ASCII mirror so subsequent
# acceptance runs reuse Gradle/Dart build caches instead of copying cold.
$resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$resolvedExecution = [IO.Path]::GetFullPath($executionRoot)
if (-not $resolvedExecution.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($resolvedExecution) -ne "morning-attendance-integration-workspace") {
    throw "Unexpected integration workspace path"
}
New-Item -ItemType Directory -Path $executionRoot -Force | Out-Null

& robocopy.exe $sourceRoot $executionRoot /MIR /R:2 /W:1 `
    /XD .git build .dart_tool .gradle releases tool `
    /XF key.properties release-key.jks windows-cacerts `
    /NFL /NDL /NJH /NJS /NP | Out-Null
$copyExitCode = $LASTEXITCODE
if ($copyExitCode -gt 7) {
    throw "Could not synchronize the ASCII integration workspace (robocopy exit $copyExitCode)"
}

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio1\jbr"
$env:PATH = (Join-Path $env:JAVA_HOME "bin") + ";" + $env:PATH
$env:HTTP_PROXY = "http://127.0.0.1:9"
$env:HTTPS_PROXY = "http://127.0.0.1:9"
$env:NO_PROXY = "localhost,127.0.0.1"
$env:GRADLE_OPTS = "-Dorg.gradle.offline=true -Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=9 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=9"

$adb = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
if (-not (Test-Path -LiteralPath $adb)) {
    throw "adb was not found under ANDROID_HOME"
}

$connectedDevices = & $adb devices
if (-not ($connectedDevices | Select-String -SimpleMatch "$DeviceId`tdevice")) {
    throw "Android device '$DeviceId' is not connected and ready"
}

$previousWindowAnimationScale = (& $adb -s $DeviceId shell settings get global window_animation_scale).Trim()
$previousTransitionAnimationScale = (& $adb -s $DeviceId shell settings get global transition_animation_scale).Trim()
$previousAnimatorDurationScale = (& $adb -s $DeviceId shell settings get global animator_duration_scale).Trim()

# The debug applicationId suffix in build.gradle.kts guarantees that these
# commands can never clear, update, or uninstall the signed production app.
& $adb -s $DeviceId uninstall $acceptancePackage 2>&1 | Out-Null
& $adb -s $DeviceId shell settings put global window_animation_scale 0
& $adb -s $DeviceId shell settings put global transition_animation_scale 0
& $adb -s $DeviceId shell settings put global animator_duration_scale 0
& $adb -s $DeviceId logcat -c

Push-Location $executionRoot
try {
    & flutter pub get --offline
    if ($LASTEXITCODE -ne 0) {
        throw "flutter pub get --offline failed with exit code $LASTEXITCODE"
    }

    & flutter drive --no-pub --keep-app-running --device-timeout 120 `
        --driver=test_driver/app_test.dart `
        --target=test_driver/app.dart `
        -d $DeviceId
    if ($LASTEXITCODE -ne 0) {
        throw "Android integration test failed with exit code $LASTEXITCODE"
    }

    $acceptancePid = (& $adb -s $DeviceId shell pidof $acceptancePackage).Trim()
    if ($acceptancePid -notmatch "^[0-9]+$") {
        throw "The acceptance app process was not running after the flow"
    }
    $criticalLogs = & $adb -s $DeviceId logcat -d --pid=$acceptancePid -v brief |
        Select-String -CaseSensitive -Pattern "FATAL EXCEPTION|E/flutter|Unhandled Exception|SQLiteException|LocaleDataException"
    if ($criticalLogs) {
        $criticalText = ($criticalLogs | ForEach-Object { $_.Line }) -join [Environment]::NewLine
        throw "Critical Android logs were found after the acceptance flow:`n$criticalText"
    }
}
finally {
    Pop-Location
    if ($previousWindowAnimationScale -match "^[0-9.]+$") {
        & $adb -s $DeviceId shell settings put global window_animation_scale $previousWindowAnimationScale
    }
    if ($previousTransitionAnimationScale -match "^[0-9.]+$") {
        & $adb -s $DeviceId shell settings put global transition_animation_scale $previousTransitionAnimationScale
    }
    if ($previousAnimatorDurationScale -match "^[0-9.]+$") {
        & $adb -s $DeviceId shell settings put global animator_duration_scale $previousAnimatorDurationScale
    }
    & $adb -s $DeviceId uninstall $acceptancePackage 2>&1 | Out-Null
}
