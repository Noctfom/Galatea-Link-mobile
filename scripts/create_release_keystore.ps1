# Galatea Link mobile 正式签名密钥创建工具，全程由 keytool 在本机交互读取密码

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$KeystorePath,

    [ValidateNotNullOrEmpty()]
    [string]$Alias = 'galatea-link-mobile',

    [string]$KeytoolPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$targetPath = [IO.Path]::GetFullPath($KeystorePath)
if (Test-Path -LiteralPath $targetPath) {
    throw "Target keystore already exists and will not be overwritten: $targetPath"
}

if ([string]::IsNullOrWhiteSpace($KeytoolPath)) {
    $keytoolCommand = Get-Command keytool.exe -ErrorAction SilentlyContinue
    if ($null -ne $keytoolCommand) {
        $KeytoolPath = $keytoolCommand.Source
    } else {
        $javaRoot = [Environment]::GetEnvironmentVariable('JAVA_HOME')
        if (-not [string]::IsNullOrWhiteSpace($javaRoot)) {
            $KeytoolPath = Join-Path $javaRoot 'bin\keytool.exe'
        }
    }
}

if ([string]::IsNullOrWhiteSpace($KeytoolPath) -or -not (Test-Path -LiteralPath $KeytoolPath)) {
    throw 'keytool.exe was not found, specify the Android Studio JBR keytool with -KeytoolPath'
}

$parentPath = Split-Path -Parent $targetPath
if ([string]::IsNullOrWhiteSpace($parentPath)) {
    throw 'The keystore must be saved in an explicit directory'
}
New-Item -ItemType Directory -Force -Path $parentPath | Out-Null

Write-Host 'keytool will ask for passwords and certificate fields interactively'
Write-Host 'Use the same strong password for the keystore and key entry'
& $KeytoolPath `
    -genkeypair `
    -v `
    -keystore $targetPath `
    -alias $Alias `
    -storetype JKS `
    -keyalg RSA `
    -keysize 4096 `
    -sigalg SHA256withRSA `
    -validity 10000

if ($LASTEXITCODE -ne 0) {
    throw "keytool failed with exit code $LASTEXITCODE"
}

$hash = Get-FileHash -LiteralPath $targetPath -Algorithm SHA256
Write-Host "Keystore created: $targetPath"
Write-Host "Alias: $Alias"
Write-Host "Keystore SHA-256: $($hash.Hash)"
Write-Host 'Create at least two offline backups now and keep the passwords in a separate password manager'
