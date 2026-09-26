<#
.SYNOPSIS
  Generates versioninfo.xml for an Avro Keyboard release.

.DESCRIPTION
  Reads the file version of the built Avro Keyboard executable and emits the
  versioninfo.xml consumed by TUpdateCheck (clsUpdateInfoDownloader.pas).
  All URLs are derived from -Tag and point to the Avro-Keyboard-Releases
  repository, so the published XML always matches the release it ships with.

.EXAMPLE
  .\tools\release\make-versioninfo.ps1 -Tag v6.0.1

.EXAMPLE
  .\tools\release\make-versioninfo.ps1 -Tag v6.0.1-beta   # prerelease: versioninfo_beta.xml
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^v\d+\.\d+\.\d+(-beta)?$')]
  [string]$Tag,

  [string]$ExePath,

  [string]$OutPath,

  [switch]$Beta,

  # Per-architecture installer URLs. Defaults are derived from -Tag; override
  # only for non-standard asset names. TUpdateCheck prefers
  # downloadurl32/downloadurl64 over downloadurl by the running exe's
  # architecture and falls back to downloadurl for legacy builds.
  [string]$DownloadUrl32,
  [string]$DownloadUrl64,

  [string]$Repo = 'raselrahmanrocky/Avro-Keyboard-Releases'
)

$ErrorActionPreference = 'Stop'

# A -beta tag is a prerelease: always emit the beta feed file.
if ($Tag -like '*-beta') { $Beta = $true }

if (-not $OutPath) {
  $name = if ($Beta) { 'versioninfo_beta.xml' } else { 'versioninfo.xml' }
  $OutPath = Join-Path (Get-Location) $name
}

if (-not $ExePath) {
  $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
  $ExePath = Join-Path $scriptDir '..\..\build\Avro Keyboard.exe'
}

if (-not (Test-Path -LiteralPath $ExePath)) {
  throw "Executable not found: $ExePath (build Avro Keyboard first)"
}
$exe = (Resolve-Path -LiteralPath $ExePath).Path

$vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
$major = $vi.FileMajorPart
$minor = $vi.FileMinorPart
$release = $vi.FileBuildPart
$build = $vi.FilePrivatePart

$tagVersion = ($Tag.Substring(1) -split '-')[0]
if ("$major.$minor.$release" -ne $tagVersion) {
  throw "Tag $Tag does not match executable version $major.$minor.$release ($exe) - bump the project version or fix -Tag"
}

# Asset names follow the release naming scheme:
#   v6.0.0-beta -> AvroKeyboard-6.0.0-beta-win32-setup.exe
#   v6.0.0      -> AvroKeyboard-6.0.0-win32-setup.exe
$assetVer  = $Tag.Substring(1)
$base = "https://github.com/$Repo"
$downloadurl = "$base/releases/download/$Tag/AvroKeyboard-$assetVer-win32-setup.exe"
$changelogurl = "$base/releases/tag/$Tag"
$productpageurl = "$base/releases/latest"
$releasedate = (Get-Date).ToString('d MMMM, yyyy', [System.Globalization.CultureInfo]::InvariantCulture)

if (-not $DownloadUrl32) { $DownloadUrl32 = "$base/releases/download/$Tag/AvroKeyboard-$assetVer-win32-setup.exe" }
if (-not $DownloadUrl64) { $DownloadUrl64 = "$base/releases/download/$Tag/AvroKeyboard-$assetVer-win64-setup.exe" }

$namedVersion = if ($Beta) { "Avro Keyboard $tagVersion BETA" } else { "Avro Keyboard $tagVersion" }

$archNodes = ''
if ($DownloadUrl32) { $archNodes += "<downloadurl32>$DownloadUrl32</downloadurl32>`n" }
if ($DownloadUrl64) { $archNodes += "<downloadurl64>$DownloadUrl64</downloadurl64>`n" }

$xml = @"
<?xml version="1.0" encoding="utf-8" ?>

<versioninfo>
<namedversion>$namedVersion</namedversion>
<versionmajor>$major</versionmajor>
<versionminor>$minor</versionminor>
<versionrevision>$release</versionrevision>
<versionbuild>$build</versionbuild>
<changelogurl>$changelogurl</changelogurl>
<downloadurl>$downloadurl</downloadurl>
$archNodes<productpageurl>$productpageurl</productpageurl>
<releasedate>$releasedate</releasedate>
</versioninfo>
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutPath, $xml.Replace("`r`n", "`n"), $utf8NoBom)

Write-Output "Wrote $OutPath"
Write-Output "  version : $major.$minor.$release.$build  (from $(Split-Path $exe -Leaf))"
Write-Output "  download: $downloadurl"
if ($DownloadUrl32) { Write-Output "  arch x86: $DownloadUrl32" }
if ($DownloadUrl64) { Write-Output "  arch x64: $DownloadUrl64" }
