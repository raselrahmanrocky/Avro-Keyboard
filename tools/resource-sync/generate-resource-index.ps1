<#
  generate-resource-index.ps1  -  PUBLISH tool (maintainer use)
  -----------------------------------------------------------------------------
  Mirrors the main repository's assets\ folder into the sibling
  Avro-Keyboard-Resource folder (the five category folders), preserving any
  *.meta.json sidecars, converting assets\Ansi*.json metadata blocks into
  sidecars, then DELEGATING index.json generation to the resource repository's
  own scanner (.github\scripts\generate-index.ps1).

  index.json is NOT generated here - the resource repository is the single
  source of truth for the catalog; this script only publishes files into it.

  Usage:
    powershell -ExecutionPolicy Bypass -File tools\resource-sync\generate-resource-index.ps1
    powershell -File tools\resource-sync\generate-resource-index.ps1 -Force        # no prompt (CI)
    powershell -File tools\resource-sync\generate-resource-index.ps1 -TargetDir D:\somewhere\Avro-Keyboard-Resource

  Defaults:
    -AssetsDir <repo>\assets
    -TargetDir <Desktop>\Avro-Keyboard-Resource   (sibling of the main repo)

  WARNING - this MIRRORS assets\: the five category folders are wiped and
  re-filled. Files added directly to those folders (not present in assets\)
  are deleted. Existing *.meta.json sidecars are preserved.
  README.md and licenses\ are never touched.
#>

[CmdletBinding()]
param(
    [string]$AssetsDir,
    [string]$TargetDir,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# tools\resource-sync -> repo root
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $AssetsDir) { $AssetsDir = Join-Path $RepoRoot 'assets' }
if (-not $TargetDir) { $TargetDir = Join-Path (Split-Path -Parent $RepoRoot) 'Avro-Keyboard-Resource' }

if (-not (Test-Path -LiteralPath $AssetsDir)) { throw "AssetsDir not found: $AssetsDir" }

# ---------------------------------------------------------------------------
# Category table: source subfolder (relative to assets\), target folder,
# glob patterns and the item "type" the app's installer understands.
# ---------------------------------------------------------------------------
$Categories = @(
    @{ id = 'ansimapping';     folder = 'AnsiMapping';    type = 'ansimapping'; sourceSub = '';       include = @('*.AvroEnco') }
    @{ id = 'keyboardlayouts'; folder = 'KeyboardLayouts'; type = 'layout';     sourceSub = 'keyboard-layouts'; include = @('*.avrolayout') }
    @{ id = 'fonts';           folder = 'Fonts';          type = 'font';       sourceSub = 'fonts';   include = @('*.ttf') }
    @{ id = 'skins';           folder = 'Skins';          type = 'skin';       sourceSub = 'skins';   include = @('*.avroskin') }
    @{ id = 'docs';            folder = 'Docs';           type = 'doc';        sourceSub = 'docs';    include = @('*.pdf', '*.htm', '*.html')
       extras = @('images') }
)

function Copy-CategoryFiles {
    param($Category)
    $srcDir = if ($Category.sourceSub -eq '') { $AssetsDir } else { Join-Path $AssetsDir $Category.sourceSub }
    $dstDir = Join-Path $TargetDir $Category.folder

    # Preserve hand-maintained *.meta.json sidecars across the wipe - they hold
    # catalog descriptions that live only in this repository. Read the bytes
    # into memory first: the source files are about to be deleted.
    $sidecars = @{}
    if (Test-Path -LiteralPath $dstDir) {
        foreach ($sc in Get-ChildItem -LiteralPath $dstDir -Filter '*.meta.json' -File -ErrorAction SilentlyContinue) {
            $sidecars[$sc.Name] = [System.IO.File]::ReadAllBytes($sc.FullName)
        }
        Remove-Item -LiteralPath $dstDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null

    $files = @()
    if (Test-Path -LiteralPath $srcDir) {
        foreach ($pattern in $Category.include) {
            $files += Get-ChildItem -LiteralPath $srcDir -Filter $pattern -File -ErrorAction SilentlyContinue
        }
        $files = $files | Sort-Object Name
        foreach ($f in $files) {
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $dstDir $f.Name) -Force
        }

        # Supporting subfolders (e.g. Docs\images referenced by the HTM guides)
        # are copied along but never listed as catalog items themselves.
        foreach ($extra in $Category.extras) {
            $extraSrc = Join-Path $srcDir $extra
            if (Test-Path -LiteralPath $extraSrc) {
                Copy-Item -LiteralPath $extraSrc -Destination (Join-Path $dstDir $extra) -Recurse -Force
            }
        }
    }

    foreach ($name in $sidecars.Keys) {
        $dest = Join-Path $dstDir $name
        if (-not (Test-Path -LiteralPath $dest)) {
            [System.IO.File]::WriteAllBytes($dest, $sidecars[$name])
        }
    }
    return $files
}

# ---------------------------------------------------------------------------
# ANSI mapping sidecars: the shipped .AvroEnco container has no human-readable
# description of its own, so the plaintext <name>.json Metadata block in
# assets\ is converted into a <name>.meta.json sidecar next to the copy. The
# resource repository's scanner picks the sidecar up (highest precedence).
# ---------------------------------------------------------------------------
function Write-AnsiSidecars {
    param($Files)
    foreach ($f in $Files) {
        $jsonPath = Join-Path $AssetsDir ($f.BaseName + '.json')
        if (-not (Test-Path -LiteralPath $jsonPath)) { continue }
        try {
            $meta = (Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json).Metadata
        } catch {
            Write-Warning "Unreadable metadata: $jsonPath ($($_.Exception.Message))"
            continue
        }
        if ($null -eq $meta) { continue }

        $ver  = [string]$meta.Version
        $dev  = [string]$meta.Developer
        $font = [string]$meta.'Suggested Font'
        $enc  = [string]$meta.Encoding
        if ($enc -eq '') { $enc = $f.BaseName }

        $en = $enc
        if ($ver -ne '')  { $en += ' - version ' + $ver }
        if ($dev -ne '')  { $en += ', by ' + $dev }
        if ($font -ne '') { $en += '. Suggested font: ' + $font }

        $sidecar = [ordered]@{ description = $en }
        if ($ver -ne '') { $sidecar.version = $ver }

        $dst = Join-Path (Join-Path $TargetDir 'AnsiMapping') ($f.BaseName + '.meta.json')
        $json = $sidecar | ConvertTo-Json -Depth 4
        [System.IO.File]::WriteAllText($dst, $json, (New-Object System.Text.UTF8Encoding($false)))
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Write-Host "Assets : $AssetsDir"
Write-Host "Target : $TargetDir"

$folders = ($Categories | ForEach-Object { $_.folder }) -join ', '
Write-Warning @"
This PUBLISHES assets\ into the resource repository ($TargetDir):
  * These category folders are WIPED and re-filled from assets\: $folders
  * Files placed directly in those folders (not present in assets\) will be DELETED
  * Existing *.meta.json sidecars are preserved
  * index.json is regenerated afterwards by the resource repo's own scanner
"@
if (-not $Force) {
    $ans = Read-Host 'Continue? [y/N]'
    if ($ans -notin @('y', 'Y')) { throw 'Aborted by user - nothing was changed.' }
}

New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null

# LICENSE refresh (README.md / licenses\ are left alone).
$licenseSrc = Join-Path $RepoRoot 'LICENSE.txt'
if (Test-Path -LiteralPath $licenseSrc) {
    Copy-Item -LiteralPath $licenseSrc -Destination (Join-Path $TargetDir 'LICENSE') -Force
}

foreach ($cat in $Categories) {
    $files = Copy-CategoryFiles -Category $cat
    if ($cat.type -eq 'ansimapping') { Write-AnsiSidecars -Files $files }
    Write-Host ("{0,-16} {1} file(s)" -f $cat.folder, @($files).Count)
}

# ---------------------------------------------------------------------------
# Delegate: the catalog is built by the resource repository's scanner only.
# ---------------------------------------------------------------------------
$scanner = Join-Path $TargetDir '.github\scripts\generate-index.ps1'
if (Test-Path -LiteralPath $scanner) {
    Write-Host "Regenerating index.json via resource repo scanner..."
    & $scanner -RepoRoot $TargetDir
} else {
    Write-Warning "Scanner not found at $scanner - run .github\scripts\generate-index.ps1 manually."
}
