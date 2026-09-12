# Galatea Link mobile 更新清单生成工具，从正式 APK 计算哈希并输出稳定版 JSON

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ApkPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VersionName,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 2147483647)]
    [int]$VersionCode,

    [ValidateRange(1, 2147483647)]
    [int]$MinimumSupportedVersionCode = 1,

    [Parameter(Mandatory = $true)]
    [Uri]$DownloadUrl,

    [Parameter(Mandatory = $true)]
    [Uri]$ReleasePageUrl,

    [string]$ReleaseNotes = '',

    [string]$OutputPath = '.\update.json',

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourcePath = [IO.Path]::GetFullPath($ApkPath)
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "APK was not found: $sourcePath"
}
if (-not $DownloadUrl.IsAbsoluteUri -or $DownloadUrl.Scheme -ne 'https') {
    throw 'DownloadUrl must be an absolute HTTPS URL'
}
if (-not $ReleasePageUrl.IsAbsoluteUri -or $ReleasePageUrl.Scheme -ne 'https') {
    throw 'ReleasePageUrl must be an absolute HTTPS URL'
}

$targetPath = [IO.Path]::GetFullPath($OutputPath)
if ((Test-Path -LiteralPath $targetPath) -and -not $Force) {
    throw "Output already exists, add -Force to replace it: $targetPath"
}
$targetParent = Split-Path -Parent $targetPath
if (-not [string]::IsNullOrWhiteSpace($targetParent)) {
    New-Item -ItemType Directory -Force -Path $targetParent | Out-Null
}

$apkHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest = [ordered]@{
    schema_version = 1
    channel = 'stable'
    version_name = $VersionName
    version_code = $VersionCode
    minimum_supported_version_code = $MinimumSupportedVersionCode
    download_url = $DownloadUrl.AbsoluteUri
    release_page_url = $ReleasePageUrl.AbsoluteUri
    sha256 = $apkHash
    release_notes = $ReleaseNotes
    published_at = (Get-Date).ToUniversalTime().ToString('o')
}

$json = $manifest | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText(
    $targetPath,
    $json + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false)
)
Write-Host "Update manifest created: $targetPath"
Write-Host "APK SHA-256: $apkHash"
