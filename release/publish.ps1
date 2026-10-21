<#
.SYNOPSIS
    Cut a release of Avro Keyboard from the private development repository into
    the public raselrahmanrocky/Avro-Keyboard repository: assets, update feeds,
    a verified source snapshot appended to main, push.

.DESCRIPTION
    The single-repo release driver. One run does:
      1. preconditions: the tag matches the built executable, the four release
         assets exist, the dev working tree is clean;
      2. the ASSET GATE: every extracted file of every asset is scanned for the
         raw IKM, the masked IKM (allowed only in the app-root keyboard
         executable) and plaintext mappings. An unsafe or unextractable asset
         is DROPped, never uploaded;
      3. a verified SNAPSHOT of the private tree: one commit, maintainer-only
         paths withheld, leak gate over the tree AND over every reachable
         object, token-less Win32 and Win64 builds;
      4. the public repository is cloned fresh, the snapshot's tree is applied
         to it (read-tree --reset -u) and committed ON TOP of the public main,
         so the public history is APPENDED to and never rewritten;
      5. the public tree is gated again (tree scan, and a history scan scoped
         to main), and the commit is pushed as a fast-forward - never a
         force-push;
      6. the release is created AT the new public commit and the gated assets
         are uploaded, then the public download URLs are HEAD-verified;
      7. the update feeds are regenerated from the live releases and committed
         to the public main (the clients read them from there) and to the
         private dev branch (so the next snapshot carries them).

    A release does not rewrite history: it appends. The one-time reset of the
    public main is a separate operation (tools\rollout\reset_public_repo.ps1),
    because a rewrite is not something a routine release should ever be able to
    do by accident.

.PARAMETER Tag
    Release tag, e.g. v6.0.2 or v6.0.2-beta. Must equal the version embedded in
    build\Avro Keyboard.exe.

.PARAMETER Repo
    Public repository (owner/name). Default: raselrahmanrocky/Avro-Keyboard.

.PARAMETER AssetsDir
    Directory holding the four release assets. Default: <repo root>\Output.

.PARAMETER Notes
    Release body text. -NotesFile wins if both are given.

.PARAMETER NotesFile
    File whose content becomes the release body.

.PARAMETER ExportDir
    Scratch directory for the verified snapshot.
    Default: ..\Avro-Keyboard-Publish\export

.PARAMETER PublicDir
    Scratch directory for the public clone.
    Default: ..\Avro-Keyboard-Publish\public

.PARAMETER InnoExtract
    Path to a compatible innoextract for the setup assets in the asset gate.

.PARAMETER SkipBuild
    Forwarded to the exporter: skip the token-less Win32/Win64 build of the
    snapshot. The run will say so.

.PARAMETER SkipCreate
    Resume mode: assume the release already exists and skip its creation.

.PARAMETER AllowDroppedAssets
    Continue when the asset gate drops an asset. Without it, a drop stops the
    run, because the release would lose a download that clients are told about.

.PARAMETER NoPush
    Do everything up to the push, then print the push command instead of
    pushing. Nothing is created or uploaded either.

.PARAMETER WhatIfOnly
    Run every LOCAL gate (asset gate, snapshot export, public clone, tree and
    history gates) and print the plan. No push, no release, no upload, no
    commit to dev.

.EXAMPLE
    release\publish.ps1 -Tag v6.0.2 -NotesFile release-notes.md

.EXAMPLE
    release\publish.ps1 -Tag v6.0.2-beta -WhatIfOnly

.NOTES
    Exit codes: 0 done, 1 a step failed, 2 a precondition could not be
    satisfied ("could not check", never a pass). Nothing is ever force-pushed
    by this script.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v\d+\.\d+\.\d+(-beta)?$')]
    [string] $Tag,

    [string] $Repo = 'raselrahmanrocky/Avro-Keyboard',
    [string] $AssetsDir = '',
    [string] $Notes = '',
    [string] $NotesFile = '',
    [string] $ExportDir = '',
    [string] $PublicDir = '',
    [string] $InnoExtract = '',
    [switch] $SkipBuild,
    [switch] $SkipCreate,
    [switch] $AllowDroppedAssets,
    [switch] $NoPush,
    [switch] $WhatIfOnly
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Info { param([string]$m) Write-Host $m }
function Write-Step { param([string]$m) Write-Host ''; Write-Host "== $m" -ForegroundColor Cyan }
function Write-Ok { param([string]$m) Write-Host "   OK  $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "   !   $m" -ForegroundColor Yellow }
function Write-Fail { param([string]$m) Write-Host "   x   $m" -ForegroundColor Red }

function Invoke-Git {
    param([string]$RepoPath, [string[]]$GitArgs)
    $out = & git -C $RepoPath @GitArgs 2>&1
    return [pscustomobject]@{ Output = @($out); Code = $LASTEXITCODE }
}

function Get-GitHubToken {
    try { $out = @('protocol=https', 'host=github.com', '') | & git credential fill 2>$null }
    catch { return '' }
    foreach ($line in @($out)) {
        if ($line -match '^password=(.+)$') { return $Matches[1] }
    }
    return ''
}

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$Exporter   = Join-Path $RepoRoot 'tools\rollout\export_fresh_repo.ps1'
$AssetGate  = Join-Path $RepoRoot 'tools\rollout\check_release_assets.ps1'
$GenManifest = Join-Path $PSScriptRoot 'gen_manifest.ps1'
$Gate       = Join-Path $RepoRoot 'tools\secrets\check-no-secret-bytes.ps1'
$assetVer   = $Tag.Substring(1)
if (-not $AssetsDir) { $AssetsDir = Join-Path $RepoRoot 'Output' }
$scratch    = Join-Path (Split-Path -Parent $RepoRoot) 'Avro-Keyboard-Publish'
if (-not $ExportDir) { $ExportDir = Join-Path $scratch 'export' }
if (-not $PublicDir) { $PublicDir = Join-Path $scratch 'public' }
$ExportDir  = [System.IO.Path]::GetFullPath($ExportDir)
$PublicDir  = [System.IO.Path]::GetFullPath($PublicDir)
$isBeta     = $Tag -like '*-beta'
$remoteUrl  = "https://github.com/$Repo.git"

# ---------------------------------------------------------------------------
# 1. Preconditions.
# ---------------------------------------------------------------------------
Write-Step 'Preconditions'

foreach ($needed in @($Exporter, $AssetGate, $GenManifest, $Gate)) {
    if (-not (Test-Path -LiteralPath $needed)) { Write-Fail "missing: $needed"; exit 2 }
}

$status = Invoke-Git -RepoPath $RepoRoot -GitArgs @('status', '--porcelain')
$tracked = @($status.Output | Where-Object { $_ -and $_ -notmatch '^\?\?' })
if ($tracked.Count -gt 0) {
    Write-Fail 'the working tree has modified or staged tracked files:'
    $tracked | ForEach-Object { Write-Host "        $_" }
    Write-Fail 'Commit or stash them first; a release must be cut from a reviewed state.'
    exit 2
}
$headBranch = (& git -C $RepoRoot rev-parse --abbrev-ref HEAD).Trim()
if ($headBranch -ne 'dev') {
    Write-Fail "HEAD is on '$headBranch'; releases are cut from 'dev'. Check it out first."
    exit 2
}
$sourceHead = (& git -C $RepoRoot rev-parse HEAD).Trim()
Write-Ok "dev working tree is clean at $sourceHead"

$exe = Join-Path $RepoRoot 'build\Avro Keyboard.exe'
if (-not (Test-Path -LiteralPath $exe)) {
    Write-Fail "the built executable is missing: $exe"
    Write-Fail 'Build the release first (tools\release\build-installers.ps1).'
    exit 2
}
$vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
$exeVer = "$($vi.FileMajorPart).$($vi.FileMinorPart).$($vi.FileBuildPart)"
$tagVer = ($Tag.Substring(1) -split '-')[0]
if ($exeVer -ne $tagVer) {
    Write-Fail "tag $Tag does not match the built executable version $exeVer."
    exit 1
}
Write-Ok "executable version  $exeVer (matches $Tag)"

$assets = @(
    "AvroKeyboard-$assetVer-win32-setup.exe",
    "AvroKeyboard-$assetVer-win64-setup.exe",
    "AvroKeyboard-$assetVer-win32-portable.zip",
    "AvroKeyboard-$assetVer-win64-portable.zip"
)
$assetPaths = @{}
$assetProblem = $false
foreach ($name in $assets) {
    $path = Join-Path $AssetsDir $name
    if (-not (Test-Path -LiteralPath $path)) { Write-Fail "missing asset: $path"; $assetProblem = $true; continue }
    $size = (Get-Item -LiteralPath $path).Length
    if ($size -le 0) { Write-Fail "asset is empty: $path"; $assetProblem = $true; continue }
    $assetPaths[$name] = $path
    Write-Ok ("asset {0} ({1:N1} MB)" -f $name, ($size / 1MB))
}
if ($assetProblem) {
    Write-Fail "expected the four assets in $AssetsDir (built by build-installers.ps1)."
    exit 2
}

$notesBody = $Notes
if ($NotesFile) {
    if (-not (Test-Path -LiteralPath $NotesFile)) { Write-Fail "-NotesFile not found: $NotesFile"; exit 2 }
    $notesBody = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $NotesFile).Path)
}
if (-not $notesBody) {
    $notesBody = "Avro Keyboard $tagVer release. Installers and portable builds are attached below; the updater feeds are served from this same repository."
}
$prereleaseFlag = $isBeta
Write-Ok "release            $Tag -> https://github.com/$Repo ($(if ($isBeta) { 'prerelease' } else { 'stable' }))"

# ---------------------------------------------------------------------------
# 2. The asset gate. Nothing is uploaded that has not passed it.
# ---------------------------------------------------------------------------
Write-Step 'Asset gate'
$gateArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $AssetGate, '-ReleaseDir', $AssetsDir)
foreach ($name in $assets) { $gateArgs += @('-Assets', $assetPaths[$name]) }
if ($InnoExtract) { $gateArgs += @('-InnoExtract', $InnoExtract) }
& powershell @gateArgs
$gateRc = $LASTEXITCODE
if ($gateRc -eq 2) { Write-Fail 'the asset gate could not run; "could not check" is never a pass.'; exit 2 }
if ($gateRc -eq 1) {
    if (-not $AllowDroppedAssets) {
        Write-Fail 'the asset gate dropped an asset. Fix it, or re-run with -AllowDroppedAssets'
        Write-Fail 'to release without it - and know that the clients are told about a download'
        Write-Fail 'that will not exist.'
        exit 1
    }
    Write-Warn 'continuing with the PASS assets only (-AllowDroppedAssets)'
}
else { Write-Ok 'every asset passed the gate' }

# ---------------------------------------------------------------------------
# 3. The verified snapshot.
# ---------------------------------------------------------------------------
Write-Step 'Snapshot: the verified single-commit export of the private tree'
if (Test-Path -LiteralPath $ExportDir) { Remove-Item -LiteralPath $ExportDir -Recurse -Force }
$exportEvidence = Join-Path $scratch 'export.json'
$exportArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Exporter,
                 '-OutDir', $ExportDir, '-Force', '-Branch', 'main',
                 '-ReleaseLabel', $Tag, '-EvidencePath', $exportEvidence)
if ($SkipBuild) { $exportArgs += '-SkipBuild' }
& powershell @exportArgs
$exportRc = $LASTEXITCODE
if ($exportRc -ne 0) {
    Write-Fail "the snapshot failed (exit $exportRc); nothing was pushed."
    exit $(if ($exportRc -eq 1) { 1 } else { 2 })
}
$snapshotSha  = (& git -C $ExportDir rev-parse HEAD).Trim()
$snapshotTree = (& git -C $ExportDir rev-parse 'HEAD^{tree}').Trim()
Write-Ok "snapshot           $snapshotSha (tree $snapshotTree)"

# The message states what the gates actually reported, not what they are
# expected to have reported: the evidence file is the exporter's own record.
$ev = Get-Content -LiteralPath $exportEvidence -Raw | ConvertFrom-Json
$buildStatus = 'SKIPPED'
if ($ev.gates.build -isnot [string] -and $ev.gates.build.win32 -eq 'PASS' -and $ev.gates.build.win64 -eq 'PASS') {
    $buildStatus = 'PASS(win32,win64)'
}
$snapshotSource = $ev.source_sha

# ---------------------------------------------------------------------------
# 4. The public clone. The snapshot is APPENDED to the public main.
# ---------------------------------------------------------------------------
Write-Step 'Public clone and append'
if (Test-Path -LiteralPath $PublicDir) { Remove-Item -LiteralPath $PublicDir -Recurse -Force }
$clone = Invoke-Git -RepoPath (Split-Path -Parent $PublicDir) -GitArgs @('clone', '--single-branch', '--branch', 'main', '--no-tags', $remoteUrl, $PublicDir)
$clone.Output | ForEach-Object { Write-Host "    $_" }
if ($clone.Code -ne 0) { Write-Fail 'the public repository could not be cloned.'; exit 2 }

$oldPublicMain = (& git -C $PublicDir rev-parse HEAD).Trim()
Write-Ok "public main        $oldPublicMain"

$fetch = Invoke-Git -RepoPath $PublicDir -GitArgs @('fetch', '--no-tags', $ExportDir, 'main')
if ($fetch.Code -ne 0) { Write-Fail 'the snapshot could not be fetched into the public clone.'; exit 1 }

$readTree = Invoke-Git -RepoPath $PublicDir -GitArgs @('read-tree', '--reset', '-u', 'FETCH_HEAD')
if ($readTree.Code -ne 0) {
    Write-Fail 'the snapshot tree could not be applied to the public clone:'
    $readTree.Output | ForEach-Object { Write-Host "        $_" }
    exit 1
}

$message = @"
Release $Tag - export of Avro-Dev@$snapshotSource; tree $snapshotTree; gates: leak=PASS history=PASS build=$buildStatus

This release appends a verified snapshot of the private Avro-Keyboard tree to
the public repository. The maintainer-only paths listed in the private
tools\rollout\exclusions.json are withheld and remain in the private
repository only. The snapshot was produced from the committed tree and gated
there; the public tree is gated again before the push.

append-to=$oldPublicMain
"@
$commit = Invoke-Git -RepoPath $PublicDir -GitArgs @('commit', '--quiet', '-m', $message)
if ($commit.Code -ne 0) {
    Write-Fail "the public commit failed (exit $($commit.Code)):"
    $commit.Output | ForEach-Object { Write-Host "        $_" }
    exit 1
}
$newPublicSha  = (& git -C $PublicDir rev-parse HEAD).Trim()
$newPublicTree = (& git -C $PublicDir rev-parse 'HEAD^{tree}').Trim()
if ($newPublicTree -ne $snapshotTree) {
    Write-Fail "the public commit tree ($newPublicTree) is not the snapshot tree ($snapshotTree)."
    exit 1
}
Write-Ok "public commit      $newPublicSha (tree matches the snapshot)"

Write-Step 'Gate the public clone'
& powershell -NoProfile -ExecutionPolicy Bypass -File $Gate -NoSecretHome -RepoRoot $PublicDir
$treeRc = $LASTEXITCODE
Write-Host ''
& powershell -NoProfile -ExecutionPolicy Bypass -File $Gate -History -Refs main -RepoRoot $PublicDir
$historyRc = $LASTEXITCODE
Write-Host ''
if ($treeRc -ne 0 -or $historyRc -ne 0) {
    Write-Fail "the public clone failed the gates (tree $treeRc, history $historyRc). Nothing was pushed."
    exit 1
}
Write-Ok 'the public clone is clean (tree scan and main-scoped history scan)'

if ($WhatIfOnly) {
    Write-Step 'Plan (-WhatIfOnly - every local gate ran; nothing was pushed, created or uploaded)'
    Write-Info "  1. push the append to main (fast-forward):"
    Write-Info "       git -C `"$PublicDir`" push origin main:main"
    Write-Info "  2. create the release $Tag at $newPublicSha and upload the gated assets"
    Write-Info "  3. HEAD-verify the four public download URLs"
    Write-Info "  4. regenerate updates\versioninfo*.xml from the live releases and commit them"
    Write-Info "     to the public main and to dev"
    exit 0
}

# ---------------------------------------------------------------------------
# 5. Push the append. A fast-forward, never a force-push.
# ---------------------------------------------------------------------------
if ($NoPush) {
    Write-Step 'Push: SKIPPED (-NoPush)'
    Write-Info 'The verified public clone is ready. Push it with:'
    Write-Host ''
    Write-Host "    git -C `"$PublicDir`" push origin main:main"
    Write-Host ''
    exit 0
}

Write-Step 'Push the append to main'
$push = Invoke-Git -RepoPath $PublicDir -GitArgs @('push', 'origin', 'main:main')
$push.Output | ForEach-Object { Write-Host "    $_" }
if ($push.Code -ne 0) {
    Write-Fail "the push failed (exit $($push.Code)). Nothing was created or uploaded."
    exit 1
}
Write-Ok "main now at $newPublicSha"

# ---------------------------------------------------------------------------
# 6. The release, at the new public commit, with the gated assets.
# ---------------------------------------------------------------------------
$token = Get-GitHubToken
if (-not $token) {
    Write-Fail 'no github.com credential available; the release API needs one.'
    Write-Fail 'The source push is done; resume with -SkipCreate after signing in.'
    exit 2
}
function Invoke-GitHubApi {
    param([string]$Uri, [string]$Method = 'GET', $Body = $null, [string]$ContentType = 'application/vnd.github+json')
    $headers = @{ 'User-Agent' = 'avro-release-tooling'; 'Accept' = 'application/vnd.github+json'; 'Authorization' = "Bearer $token" }
    $params = @{ Method = $Method; Uri = $Uri; Headers = $headers }
    if ($null -ne $Body) { $params['Body'] = $Body }
    if ($ContentType) { $params['ContentType'] = $ContentType }
    try { return Invoke-RestMethod @params }
    catch {
        $status = ''
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        throw "GitHub API $Method $Uri failed ($status): $($_.Exception.Message)"
    }
}

Write-Step 'Create the release'
$releaseId = $null
if ($SkipCreate) {
    Write-Warn 'release creation skipped (-SkipCreate)'
    try {
        $existing = Invoke-GitHubApi -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag"
        $releaseId = $existing.id
        Write-Ok "using the existing release $releaseId"
    }
    catch { Write-Fail "could not resolve the existing release $Tag`: $($_.Exception.Message)"; exit 1 }
}
else {
    $payload = @{
        tag_name         = $Tag
        target_commitish = $newPublicSha
        name             = "Avro Keyboard $assetVer"
        body             = $notesBody
        draft            = $false
        prerelease       = $prereleaseFlag
    }
    try {
        $release = Invoke-GitHubApi -Uri "https://api.github.com/repos/$Repo/releases" -Method 'POST' -Body ($payload | ConvertTo-Json -Depth 4)
        $releaseId = $release.id
        Write-Ok "created release $Tag (id $releaseId) at $newPublicSha"
    }
    catch {
        $message2 = $_.Exception.Message
        if ($message2 -match '\(422\)') {
            Write-Warn "the release $Tag already exists; continuing with it (resume semantics)"
            try {
                $existing = Invoke-GitHubApi -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag"
                $releaseId = $existing.id
                Write-Ok "using the existing release $releaseId"
            }
            catch { Write-Fail "could not resolve the existing release $Tag`: $($_.Exception.Message)"; exit 1 }
        }
        else { Write-Fail $message2; exit 1 }
    }
}

Write-Step "Upload assets ($releaseId)"
$existingAssets = @()
for ($attempt = 1; $attempt -le 4; $attempt++) {
    try { $assetRaw = Invoke-GitHubApi -Uri "https://api.github.com/repos/$Repo/releases/$releaseId/assets?per_page=100" }
    catch { Write-Fail $_.Exception.Message; exit 1 }
    # PowerShell 5.1 can hand a JSON array back as ONE nested element, so the
    # list is flattened explicitly before it is filtered.
    $rawAssets = @()
    foreach ($a in $assetRaw) { $rawAssets += $a }
    $existingAssets = @($rawAssets | Where-Object { $_ -and $_.PSObject.Properties['name'] })
    if ($existingAssets.Count -gt 0 -or $attempt -eq 4) { break }
    Write-Warn "the asset list came back empty (attempt $attempt); retrying in 5s"
    Start-Sleep -Seconds 5
}
$existingNames = @($existingAssets | ForEach-Object { $_.name })
$uploadFailed = $false
foreach ($name in $assets) {
    if ($existingNames -contains $name) { Write-Warn "asset already on the release, skipping: $name"; continue }
    $path = $assetPaths[$name]
    try {
        $uploaded = Invoke-RestMethod -Method 'POST' `
            -Uri "https://uploads.github.com/repos/$Repo/releases/$releaseId/assets?name=$name" `
            -Headers @{ 'User-Agent' = 'avro-release-tooling'; 'Accept' = 'application/vnd.github+json'; 'Authorization' = "Bearer $token" } `
            -ContentType 'application/octet-stream' -InFile $path
        Write-Ok "uploaded $name ($($uploaded.size) bytes)"
    }
    catch {
        Write-Fail "upload failed for $name`: $($_.Exception.Message)"
        $uploadFailed = $true
    }
}
if ($uploadFailed) { Write-Fail 'Not every asset is on the release. Resume with -SkipCreate.'; exit 1 }

Write-Step 'Verify public download URLs'
$verifyFailed = $false
foreach ($name in $assets) {
    $url = "https://github.com/$Repo/releases/download/$Tag/$name"
    $ok = $false
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        try {
            $resp = Invoke-WebRequest -Method Head -Uri $url -UseBasicParsing -MaximumRedirection 10
            if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400) { $ok = $true; break }
        }
        catch { if ($attempt -lt 6) { Start-Sleep -Seconds 5 } }
    }
    if ($ok) { Write-Ok "reachable  $name" }
    else { Write-Fail "not reachable after 6 attempts: $url"; $verifyFailed = $true }
}
if ($verifyFailed) { Write-Fail 'The release exists but some downloads do not answer.'; exit 1 }

# ---------------------------------------------------------------------------
# 7. The feed follow-up. The clients read the feeds from the public main.
# ---------------------------------------------------------------------------
Write-Step 'Update feeds (updates\versioninfo*.xml)'
& powershell -NoProfile -ExecutionPolicy Bypass -File $GenManifest -Repo $Repo
if ($LASTEXITCODE -ne 0) { Write-Fail "gen_manifest.ps1 failed (exit $LASTEXITCODE)."; exit $LASTEXITCODE }

$feedFiles = @('updates/versioninfo.xml', 'updates/versioninfo_beta.xml')
$publicAdd = Invoke-Git -RepoPath $PublicDir -GitArgs (@('add', '--') + $feedFiles)
if ($publicAdd.Code -ne 0) { Write-Fail 'the feed files could not be staged in the public clone.'; exit 1 }
$publicStaged = Invoke-Git -RepoPath $PublicDir -GitArgs @('diff', '--cached', '--quiet')
if ($publicStaged.Code -eq 0) {
    Write-Warn 'the feeds already match the live releases; nothing to commit'
}
else {
    $publicCommit = Invoke-Git -RepoPath $PublicDir -GitArgs @('commit', '--quiet', '-m', "chore(release): write $Tag update manifests")
    if ($publicCommit.Code -ne 0) { Write-Fail 'the feed commit in the public clone failed.'; exit 1 }
    $feedPush = Invoke-Git -RepoPath $PublicDir -GitArgs @('push', 'origin', 'main:main')
    if ($feedPush.Code -ne 0) { Write-Fail 'the feed commit could not be pushed.'; exit 1 }
    Write-Ok "feeds committed and pushed to the public main"
}

# The private dev branch keeps the same feed files, so the next snapshot
# carries them and the two never drift.
$devAdd = Invoke-Git -RepoPath $RepoRoot -GitArgs (@('add', '--') + $feedFiles)
if ($devAdd.Code -eq 0) {
    $devStaged = Invoke-Git -RepoPath $RepoRoot -GitArgs @('diff', '--cached', '--quiet')
    if ($devStaged.Code -ne 0) {
        $devCommit = Invoke-Git -RepoPath $RepoRoot -GitArgs @('commit', '--quiet', '-m', "chore(release): write $Tag update manifests")
        if ($devCommit.Code -eq 0) { Write-Ok 'feeds committed to dev' }
        else { Write-Warn 'the feed commit on dev failed; the public main is already correct.' }
    }
    else { Write-Warn 'the feeds on dev already match; nothing to commit' }
}

Write-Step 'Released'
Write-Info "  release   https://github.com/$Repo/releases/tag/$Tag"
Write-Info "  main      $newPublicSha"
Write-Info "  stable    https://raw.githubusercontent.com/$Repo/main/updates/versioninfo.xml"
Write-Info "  beta      https://raw.githubusercontent.com/$Repo/main/updates/versioninfo_beta.xml"
exit 0
