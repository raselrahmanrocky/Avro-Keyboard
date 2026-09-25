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
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^v\d+\.\d+\.\d+$')]
  [string]$Tag,

  [string]$ExePath,

  [string]$OutPath = (Join-Path (Get-Location) 'versioninfo.xml'),

  [string]$Repo = 'raselrahmanrocky/Avro-Keyboard-Releases'
)

$ErrorActionPreference = 'Stop'

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

$tagVersion = $Tag.Substring(1)
if ("$major.$minor.$release" -ne $tagVersion) {
  throw "Tag $Tag does not match executable version $major.$minor.$release ($exe) - bump the project version or fix -Tag"
}

$base = "https://github.com/$Repo"
$downloadurl = "$base/releases/download/$Tag/Setup_AvroKeyboard.exe"
$changelogurl = "$base/releases/tag/$Tag"
$productpageurl = "$base/releases/latest"
$releasedate = (Get-Date).ToString('d MMMM, yyyy', [System.Globalization.CultureInfo]::InvariantCulture)

$xml = @"
<?xml version="1.0" encoding="utf-8" ?>

<versioninfo>
<namedversion>Avro Keyboard $tagVersion</namedversion>
<versionmajor>$major</versionmajor>
<versionminor>$minor</versionminor>
<versionrevision>$release</versionrevision>
<versionbuild>$build</versionbuild>
<changelogurl>$changelogurl</changelogurl>
<downloadurl>$downloadurl</downloadurl>
<productpageurl>$productpageurl</productpageurl>
<releasedate>$releasedate</releasedate>
</versioninfo>
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutPath, $xml.Replace("`r`n", "`n"), $utf8NoBom)

Write-Output "Wrote $OutPath"
Write-Output "  version : $major.$minor.$release.$build  (from $(Split-Path $exe -Leaf))"
Write-Output "  download: $downloadurl"
