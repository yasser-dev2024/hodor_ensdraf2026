param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId
)

$ErrorActionPreference = "Stop"
$sourceRoot = Split-Path -Parent $PSScriptRoot
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("attendance-integration-" + [Guid]::NewGuid().ToString("N"))

New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
try {
    Get-ChildItem -LiteralPath $sourceRoot -Force |
        Where-Object { $_.Name -notin @("build", ".dart_tool", ".git", "releases", "tool") } |
        Copy-Item -Destination $temporaryRoot -Recurse -Force

    # Flutter Drive reads the namespace when launching and the applicationId
    # when installing. Give both a literal test-only value so it can never
    # launch, update, or uninstall the production package.
    $temporaryGradle = Join-Path $temporaryRoot "android\app\build.gradle.kts"
    $gradleText = Get-Content -LiteralPath $temporaryGradle -Raw -Encoding UTF8
    $gradleText = $gradleText.Replace(
        'applicationId = "sa.school.attendance.morning_student_attendance"',
        'applicationId = "sa.school.attendance.morning_student_attendance.debug"'
    ).Replace(
        'namespace = "sa.school.attendance.morning_student_attendance"',
        'namespace = "sa.school.attendance.morning_student_attendance.debug"'
    )
    [IO.File]::WriteAllText($temporaryGradle, $gradleText, [Text.UTF8Encoding]::new($false))

    $temporaryActivity = Join-Path $temporaryRoot "android\app\src\main\kotlin\sa\school\attendance\morning_student_attendance\MainActivity.kt"
    $activityText = Get-Content -LiteralPath $temporaryActivity -Raw -Encoding UTF8
    $activityText = $activityText.Replace(
        'package sa.school.attendance.morning_student_attendance',
        'package sa.school.attendance.morning_student_attendance.debug'
    )
    [IO.File]::WriteAllText($temporaryActivity, $activityText, [Text.UTF8Encoding]::new($false))

    $env:JAVA_HOME = "C:\Program Files\Android\Android Studio1\jbr"
    $env:PATH = (Join-Path $env:JAVA_HOME "bin") + ";" + $env:PATH
    $env:HTTP_PROXY = "http://127.0.0.1:9"
    $env:HTTPS_PROXY = "http://127.0.0.1:9"
    $env:NO_PROXY = "localhost,127.0.0.1"
    $env:GRADLE_OPTS = "-Dorg.gradle.offline=true -Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=9 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=9"

    Push-Location $temporaryRoot
    try {
        & flutter pub get --offline
        if ($LASTEXITCODE -ne 0) {
            throw "flutter pub get --offline failed with exit code $LASTEXITCODE"
        }
        & flutter drive --no-pub --keep-app-running --driver=test_driver/app_test.dart --target=test_driver/app.dart -d $DeviceId
        if ($LASTEXITCODE -ne 0) {
            throw "Android integration test failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    $resolvedTemp = [IO.Path]::GetFullPath($temporaryRoot)
    $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemp).StartsWith("attendance-integration-") -and
        (Test-Path -LiteralPath $resolvedTemp)) {
        try {
            Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
        }
        catch {
            Write-Warning "Temporary integration directory could not be removed yet: $resolvedTemp"
        }
    }
}
