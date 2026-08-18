param(
    [string]$Alias = "attendance"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$androidRoot = Join-Path $projectRoot "android"
$keyPath = Join-Path $androidRoot "release-key.jks"
$propertiesPath = Join-Path $androidRoot "key.properties"
$temporaryKeyPath = Join-Path ([IO.Path]::GetTempPath()) ("attendance-release-" + [Guid]::NewGuid().ToString("N") + ".jks")
$keytool = "C:\Program Files\Android\Android Studio1\jbr\bin\keytool.exe"

if ((Test-Path -LiteralPath $keyPath) -or (Test-Path -LiteralPath $propertiesPath)) {
    throw "Signing files already exist. Move or back them up before generating new keys."
}
if (-not (Test-Path -LiteralPath $keytool)) {
    throw "keytool was not found at the configured Android Studio JDK path."
}

$bytes = New-Object byte[] 24
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$password = [Convert]::ToBase64String($bytes).Replace("/", "A").Replace("+", "B").TrimEnd("=")

try {
    # keytool on some Windows installations rejects non-Latin destination paths.
    # Generate in the ASCII-safe temp directory, then move with PowerShell.
    & $keytool -genkeypair -v -keystore $temporaryKeyPath -storepass $password -keypass $password -alias $Alias -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=School Attendance, OU=Student Affairs, O=School, L=Riyadh, C=SA"
    if ($LASTEXITCODE -ne 0) { throw "keytool failed with exit code $LASTEXITCODE" }
    Move-Item -LiteralPath $temporaryKeyPath -Destination $keyPath
}
finally {
    if (Test-Path -LiteralPath $temporaryKeyPath) {
        Remove-Item -LiteralPath $temporaryKeyPath -Force
    }
}

$propertiesContent = @"
storePassword=$password
keyPassword=$password
keyAlias=$Alias
storeFile=../release-key.jks
"@
[IO.File]::WriteAllText($propertiesPath, $propertiesContent, (New-Object Text.UTF8Encoding($false)))

Write-Output "Android release signing files were generated. Back up android/release-key.jks and android/key.properties securely."
