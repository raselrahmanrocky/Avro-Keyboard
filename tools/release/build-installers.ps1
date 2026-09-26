<#
.SYNOPSIS
  Builds the four Avro Keyboard release artifacts per architecture:
    AvroKeyboard-<ver>[-beta]-win32-setup.exe      (installed edition)
    AvroKeyboard-<ver>[-beta]-win64-setup.exe      (installed edition)
    AvroKeyboard-<ver>[-beta]-win32-portable.zip   (portable edition)
    AvroKeyboard-<ver>[-beta]-win64-portable.zip   (portable edition)

.DESCRIPTION
  <ver> comes from the built executable's file version (override with -Version);
  -Beta appends the -beta channel suffix (e.g. 6.0.0-beta), plain runs produce
  stable names (e.g. 6.0.0).

  Two passes run per architecture:
    1. Installed pass: clean build\ -> msbuild WholeProject.groupproj
       (Config=Release, Platform=Win32/Win64) -> remove build\dcu (compiled
       intermediates must never ship) -> rename outputs like build-ce.bat ->
       PE arch guard -> ISCC avro-setup.iss /DSetupBaseName=AvroKeyboard-<ver>-<arch>-setup
    2. Portable pass: force {$Define PortableOn} ON in ProjectDefines.inc (the
       documented portable-edition switch; settings move to Settings.xml and
       data resolves next to the exe) -> same build/rename/guard pipeline ->
       stage the payload (binaries, Database.db3, autodict.dct, layouts, skins,
       AnsiMapping, docs, Virtual Font, fonts, README) under a top-level folder
       -> zip to Output\AvroKeyboard-<ver>-<arch>-portable.zip.

  The portable switch is forced OFF before the installed passes and ON before
  the portable passes, whatever state ProjectDefines.inc started in, and every
  pass asserts the compiled edition against the PortableOn-only "Virtual Font"
  string before packaging. The original file is restored byte-for-byte in the
  final finally block, so the working tree is untouched even when a pass
  fails. build\ is cleaned before every pass, so each build is complete and
  never mixes architectures or editions.

.EXAMPLE
  .\tools\release\build-installers.ps1            # stable names, both arches

.EXAMPLE
  .\tools\release\build-installers.ps1 -Beta      # *-beta names

.EXAMPLE
  .\tools\release\build-installers.ps1 -Arch x64 -Beta
#>
[CmdletBinding()]
param(
  [ValidateSet('x86', 'x64', 'both')]
  [string]$Arch = 'both',

  [switch]$Beta,

  # Version override (X.Y.Z or X.Y.Z-beta). Defaults to the file version of
  # the freshly built "Avro Keyboard.exe" plus the -Beta suffix if given.
  [ValidatePattern('^\d+\.\d+\.\d+(-beta)?$')]
  [string]$Version,

  [string]$ISCC
)

$ErrorActionPreference = 'Stop'

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..\..')).Path

$rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat'
if (-not (Test-Path -LiteralPath $rsvars)) { throw "rsvars.bat not found: $rsvars" }

if (-not $ISCC) {
    foreach ($candidate in @(
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe'
    )) {
        if (Test-Path -LiteralPath $candidate) { $ISCC = $candidate; break }
    }
}
if (-not $ISCC -or -not (Test-Path -LiteralPath $ISCC)) {
    throw 'ISCC.exe not found. Install Inno Setup 6 or pass -ISCC <path>.'
}

$buildDir    = Join-Path $repoRoot 'build'
$dcuDir      = Join-Path $buildDir 'dcu'
$issPath     = Join-Path $repoRoot 'avro-setup.iss'
$outputDir   = Join-Path $repoRoot 'Output'
$assetsDir   = Join-Path $repoRoot 'assets'
$definesPath = Join-Path $repoRoot 'ProjectDefines.inc'

# build-ce.bat rename mapping - avro-setup.iss references the spaced names.
$renameMap = [ordered]@{
    'Avro_Keyboard.exe'       = 'Avro Keyboard.exe'
    'Avro_Spell_Checker.exe'  = 'Avro Spell Checker.exe'
    'LayoutEditor.exe'        = 'Layout Editor.exe'
    'SkinDesigner.exe'        = 'Skin Designer.exe'
    'Avro_Text_Converter.exe' = 'Avro Text Converter.exe'
}
# AvroSpell.dll is a required output but is never renamed.
$requiredAfterBuild = @($renameMap.Keys) + 'AvroSpell.dll'

function Get-PeMachine {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    return [BitConverter]::ToUInt16($bytes, $peOffset + 4)
}

function Assert-Arch {
    param([string]$Path, [uint16]$Expected, [string]$Label)
    $machine = Get-PeMachine $Path
    if ($machine -ne $Expected) {
        throw ("{0}: {1} is machine 0x{2:X4}, expected 0x{3:X4}" -f `
            $Label, (Split-Path $Path -Leaf), $machine, $Expected)
    }
}

function Clear-BuildOutputs {
    # Removes previous pass binaries AND the dcu folder: the dcu purge also
    # guarantees the PortableOn toggle always triggers a full recompile.
    Get-ChildItem -LiteralPath $buildDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.exe', '.dll' } |
        Remove-Item -Force
    foreach ($stale in $renameMap.Values) {
        $p = Join-Path $buildDir $stale
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
    if (Test-Path -LiteralPath $dcuDir) { Remove-Item -LiteralPath $dcuDir -Recurse -Force }
}

function Invoke-GroupBuild {
    param([string]$Platform, [string]$Label)
    Write-Host ("-- msbuild WholeProject.groupproj  Config=Release Platform={0}" -f $Platform)
    cmd /c "call `"$rsvars`" && msbuild WholeProject.groupproj /t:Build /p:Config=Release /p:Platform=$Platform /v:minimal /nologo"
    if ($LASTEXITCODE -ne 0) { throw "msbuild failed for $Label (exit $LASTEXITCODE)" }
    foreach ($name in $requiredAfterBuild) {
        if (-not (Test-Path -LiteralPath (Join-Path $buildDir $name))) {
            throw "Expected output missing after $Label build: $name"
        }
    }
}

function Rename-BuildOutputs {
    foreach ($from in $renameMap.Keys) {
        Move-Item -LiteralPath (Join-Path $buildDir $from) -Destination (Join-Path $buildDir $renameMap[$from]) -Force
    }
}

function Assert-AllArch {
    param([uint16]$Expected, [string]$Label)
    $outputs = Get-ChildItem -LiteralPath $buildDir -File | Where-Object { $_.Extension -in '.exe', '.dll' }
    foreach ($f in $outputs) { Assert-Arch -Path $f.FullName -Expected $Expected -Label $Label }
    Write-Host ("-- arch guard OK: {0} native output(s) are 0x{1:X4}" -f $outputs.Count, $Expected) -ForegroundColor Green
}

function Get-ExeFileVersion {
    # "6.0.0.0" -> "6.0.0"
    $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $buildDir 'Avro Keyboard.exe'))
    return '{0}.{1}.{2}' -f $vi.FileMajorPart, $vi.FileMinorPart, $vi.FileBuildPart
}

function Set-PortableOnState {
    # Forces the portable-edition switch into the requested state regardless
    # of ProjectDefines.inc's current state (active, commented or already
    # correct). The line must exist in one of those two forms.
    param([bool]$Enabled)
    $text = [IO.File]::ReadAllText($definesPath)
    if ($text -notmatch '(?m)^(\s*)(//\s*)?\{\$Define PortableOn\}\s*$') {
        throw "No '{`$Define PortableOn}' line (active or commented) found in ProjectDefines.inc"
    }
    if ($Enabled) {
        $new = $text -replace '(?m)^(\s*)//\s*(\{\$Define PortableOn\})\s*$', '$1$2'
        if ($new -notmatch '(?m)^\s*\{\$Define PortableOn\}\s*$') {
            throw 'Could not force PortableOn ON in ProjectDefines.inc'
        }
    } else {
        $new = $text -replace '(?m)^(\s*)(\{\$Define PortableOn\})\s*$', '$1// $2'
        if ($new -match '(?m)^\s*\{\$Define PortableOn\}\s*$') {
            throw 'Could not force PortableOn OFF in ProjectDefines.inc'
        }
    }
    if ($new -ne $text) {
        [IO.File]::WriteAllText($definesPath, $new, (New-Object System.Text.UTF8Encoding($false)))
    }
    Write-Host ("-- ProjectDefines.inc PortableOn = {0}" -f $(if ($Enabled) { 'ON' } else { 'OFF' })) -ForegroundColor Cyan
}

function Assert-Edition {
    # uForm1.pas references 'Virtual Font\Siyamrupali.ttf' only inside
    # {$IFDEF PortableOn} blocks, so the UTF-16 string in the binary proves
    # which edition was compiled.
    param([ValidateSet('installed', 'portable')][string]$Expected, [string]$Label)
    $bytes = [IO.File]::ReadAllBytes((Join-Path $buildDir 'Avro Keyboard.exe'))
    $found = [Text.Encoding]::Unicode.GetString($bytes).Contains('Virtual Font')
    $want  = ($Expected -eq 'portable')
    if ($found -ne $want) {
        throw ("{0}: expected an {1} build but the exe's PortableOn marker says {2}" -f `
            $Label, $Expected, $(if ($found) { 'portable' } else { 'installed' }))
    }
    Write-Host ("-- edition guard OK: {0} build (Virtual Font marker {1})" -f `
        $Expected, $(if ($found) { 'present' } else { 'absent' })) -ForegroundColor Green
}

function Invoke-InstalledPass {
    param([string]$Platform, [string]$ArchLabel, [uint16]$Machine)

    $label = "installed $ArchLabel ($Platform)"
    Write-Host ''
    Write-Host ("==== PASS {0} ====" -f $label) -ForegroundColor Cyan

    Clear-BuildOutputs
    Invoke-GroupBuild -Platform $Platform -Label $label

    # dcu intermediates out before packaging (iss also excludes them).
    if (Test-Path -LiteralPath $dcuDir) { Remove-Item -LiteralPath $dcuDir -Recurse -Force }

    Rename-BuildOutputs
    Assert-AllArch -Expected $Machine -Label $label
    Assert-Edition -Expected 'installed' -Label $label

    # Resolve the artifact version from the freshly built exe (after rename).
    if (-not $script:VerName) {
        $exeVer = Get-ExeFileVersion
        $script:VerName = if ($Version) { $Version } else { $exeVer }
        if ($Beta -and $script:VerName -notlike '*-*') { $script:VerName += '-beta' }
        Write-Host ("-- artifact version: {0} (exe {1})" -f $script:VerName, $exeVer) -ForegroundColor Green
        if ($Version -and $exeVer -ne ($script:VerName -replace '-beta$', '')) {
            Write-Warning "-Version $Version does not match exe file version $exeVer"
        }
    }

    $setupName = "AvroKeyboard-$($script:VerName)-$ArchLabel-setup"
    Write-Host "-- ISCC $setupName"
    # Antivirus can hold the freshly written Setup.exe for a few seconds
    # (EndUpdateResource error 110) - retry before giving up.
    $isccOk = $false
    for ($attempt = 1; $attempt -le 3 -and -not $isccOk; $attempt++) {
        & $ISCC "/DSetupBaseName=$setupName" $issPath
        $isccOk = ($LASTEXITCODE -eq 0)
        if (-not $isccOk) {
            Write-Warning ("ISCC attempt {0} failed (exit {1}); retrying..." -f $attempt, $LASTEXITCODE)
            Start-Sleep -Seconds 5
        }
    }
    if (-not $isccOk) { throw "ISCC failed after 3 attempts (exit $LASTEXITCODE)" }

    $setupPath = Join-Path $outputDir "$setupName.exe"
    if (-not (Test-Path -LiteralPath $setupPath)) { throw "Installer not produced: $setupPath" }
    $size = [Math]::Round((Get-Item -LiteralPath $setupPath).Length / 1MB, 1)
    Write-Host ("-- OK {0} ({1} MB)" -f $setupPath, $size) -ForegroundColor Green
}

function Copy-Tree {
    # Copies the content of $Source into $Destination (recursive, creates dirs).
    # .gitkeep placeholders never ship.
    param([string]$Source, [string]$Destination)
    Get-ChildItem -LiteralPath $Source -Recurse -File |
        Where-Object { $_.Name -ne '.gitkeep' } |
        ForEach-Object {
        $rel = $_.FullName.Substring($Source.Length).TrimStart('\')
        $dest = Join-Path $Destination $rel
        $destDir = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
    }
}

function New-PortableZip {
    param([string]$Platform, [string]$ArchLabel, [uint16]$Machine)

    $label = "portable $ArchLabel ($Platform)"
    Write-Host ''
    Write-Host ("==== PASS {0} ====" -f $label) -ForegroundColor Cyan

    Clear-BuildOutputs
    Invoke-GroupBuild -Platform $Platform -Label $label
    if (Test-Path -LiteralPath $dcuDir) { Remove-Item -LiteralPath $dcuDir -Recurse -Force }
    Rename-BuildOutputs
    Assert-AllArch -Expected $Machine -Label $label
    Assert-Edition -Expected 'portable' -Label $label

    $stageName  = "AvroKeyboard-$($script:VerName)-$ArchLabel"
    $stageRoot  = Join-Path ([IO.Path]::GetTempPath()) ("avro_stage_" + [Guid]::NewGuid().ToString('N'))
    $stageApp   = Join-Path $stageRoot $stageName
    $zipPath    = Join-Path $outputDir "$stageName-portable.zip"
    try {
        New-Item -ItemType Directory -Path $stageApp -Force | Out-Null

        # Binaries (dcu already purged; belt and braces: skip it anyway).
        Get-ChildItem -LiteralPath $buildDir -Recurse -File |
            Where-Object { $_.FullName -notlike "$dcuDir\*" -and $_.Name -ne '.gitkeep' } |
            ForEach-Object {
                $rel = $_.FullName.Substring($buildDir.Length).TrimStart('\')
                $dest = Join-Path $stageApp $rel
                $destDir = Split-Path -Parent $dest
                if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
            }

        # Payload mirroring avro-setup.iss {app}/{commonappdata} layout, with
        # data resolving next to the exe because PortableOn sets
        # GetAvroDataDir = exe folder.
        Copy-Tree -Source (Join-Path $assetsDir 'docs') -Destination $stageApp
        foreach ($enco in (Get-ChildItem -LiteralPath $assetsDir -Filter 'Ansi V*.AvroEnco')) {
            $dest = Join-Path $stageApp 'AnsiMapping'
            if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
            Copy-Item -LiteralPath $enco.FullName -Destination $dest -Force
        }
        Copy-Item -LiteralPath (Join-Path $assetsDir 'autodict.dct')    -Destination $stageApp -Force
        Copy-Item -LiteralPath (Join-Path $assetsDir 'Database.db3')    -Destination $stageApp -Force
        Copy-Tree -Source (Join-Path $assetsDir 'skins')                -Destination (Join-Path $stageApp 'Skin')
        Copy-Tree -Source (Join-Path $assetsDir 'keyboard-layouts')     -Destination (Join-Path $stageApp 'Keyboard Layouts')

        # uForm1 startup installs this exact file from beside the exe.
        New-Item -ItemType Directory -Path (Join-Path $stageApp 'Virtual Font') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $assetsDir 'fonts\SiyamRupali.ttf') `
                  -Destination (Join-Path $stageApp 'Virtual Font\Siyamrupali.ttf') -Force
        # Full manual-install font set.
        Copy-Tree -Source (Join-Path $assetsDir 'fonts') -Destination (Join-Path $stageApp 'fonts')

        $readme = @"
Avro Keyboard $($script:VerName) - Portable Edition ($ArchLabel)
==============================================================

Run "Avro Keyboard.exe". No installation, no registry changes:
all settings are stored in Settings.xml next to the exe.

What is included
- Spell checker (Database.db3), auto-correct dictionary (autodict.dct),
  keyboard layouts and skins - work out of the box on a fresh machine.
- Siyam Rupali is loaded automatically from "Virtual Font\" while running.
- Fonts: double-click the .ttf files in "fonts\" to install them, or use
  the in-app Resource Center (requires internet).
- Help documentation is in this folder ("Overview.pdf" and friends).

Upgrading: extract this archive over the previous portable folder.
"@
        Set-Content -LiteralPath (Join-Path $stageApp 'README.txt') -Value $readme -Encoding UTF8

        if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
        Compress-Archive -Path $stageApp -DestinationPath $zipPath -CompressionLevel Optimal
        if (-not (Test-Path -LiteralPath $zipPath)) { throw "Portable zip not produced: $zipPath" }
        $size = [Math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 1)
        Write-Host ("-- OK {0} ({1} MB)" -f $zipPath, $size) -ForegroundColor Green
    }
    finally {
        if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
    }
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

$passes = @()
if ($Arch -in 'x86', 'both') { $passes += @{ Platform = 'Win32'; Label = 'win32'; Machine = [uint16]0x014C } }
if ($Arch -in 'x64', 'both') { $passes += @{ Platform = 'Win64'; Label = 'win64'; Machine = [uint16]0x8664 } }

$script:VerName = $null

# Original state of ProjectDefines.inc - captured before any forcing and
# restored byte-for-byte in the final finally, so the working tree is
# untouched whatever state the file started in or how a pass fails.
$definesBackup = [IO.File]::ReadAllBytes($definesPath)

try {
    # 1. Installed editions: the portable switch must be OFF.
    Set-PortableOnState -Enabled $false
    foreach ($pass in $passes) {
        Invoke-InstalledPass -Platform $pass.Platform -ArchLabel $pass.Label -Machine $pass.Machine
    }

    # 2. Portable editions: the portable switch must be ON.
    Set-PortableOnState -Enabled $true
    foreach ($pass in $passes) {
        New-PortableZip -Platform $pass.Platform -ArchLabel $pass.Label -Machine $pass.Machine
    }
}
finally {
    [IO.File]::WriteAllBytes($definesPath, $definesBackup)
    Write-Host ''
    Write-Host '-- ProjectDefines.inc restored to its original state' -ForegroundColor Cyan
}

Write-Host ''
Write-Host "Done. Release artifacts in Output\ (version $($script:VerName)):" -ForegroundColor Cyan
Get-ChildItem -LiteralPath $outputDir -File |
    Where-Object { $_.Name -like "AvroKeyboard-$($script:VerName)*" } |
    Sort-Object Name |
    ForEach-Object { Write-Host ("  {0}  ({1} MB)" -f $_.Name, [Math]::Round($_.Length / 1MB, 1)) }
