<#
.SYNOPSIS
    Cut a release of Avro Keyboard from the private development repository into
    the public raselrahmanrocky/Avro-Keyboard repository: assets, update feeds,
    scrubbed history, push.

.DESCRIPTION
    The single-repo release driver. One run does:
      1. preconditions: the tag matches the built executable, the four release
         assets exist, the dev working tree is clean;
      2. create the GitHub release on raselrahmanrocky/Avro-Keyboard with
         target_commitish main (prerelease when the tag ends in -beta);
      3. upload the four assets; re-runs skip assets that already exist, so a
         failed run is resumed by re-invoking with -SkipCreate;
      4. HEAD-verify every asset's public download URL (with retries for CDN lag);
      5. release\gen_manifest.ps1 -> updates\versioninfo.xml and
         versioninfo_beta.xml, then commit them to the dev branch
         ("chore(release): write <tag> update manifests");
      6. tools\rollout\export_history_repo.ps1: rewrite the dev history after the
         upstream base with the secret scrubbed and maintainer paths withheld,
         and verify it (leak gate, tree equality, token-less builds);
      7. push the verified result to main - a fast-forward, never a force-push.

    Everything the client needs is served from the ONE repository:
      feed stable  raw.githubusercontent.com/raselrahmanrocky/Avro-Keyboard/main/updates/versioninfo.xml
      feed beta    .../updates/versioninfo_beta.xml
      assets       github.com/raselrahmanrocky/Avro-Keyboard/releases/download/<tag>/...

    A history rewrite does not revoke anything: clones that already exist keep
    the old commits. See docs\ROLLOUT_CHECKLIST.md in the private repository.

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
    Scratch directory for the history rewrite. Default: ..\Avro-Keyboard-Publish
    next to the development repository.

.PARAMETER SkipBuild
    Forwarded to export_history_repo.ps1: skip the token-less Win32/Win64 build
    of the exported tree. The run will say so.

.PARAMETER SkipCreate
    Resume mode: assume the release already exists (creation is step 2) and skip
    straight to uploading / verifying / publishing.

.PARAMETER NoPush
    Do everything, verify everything, commit the manifests, build the export -
    and print the push command instead of pushing.

.PARAMETER WhatIfOnly
    Resolve the preconditions and print the plan; no network writes, no export.

.EXAMPLE
    release\publish.ps1 -Tag v6.0.2 -NotesFile release-notes.md

.EXAMPLE
    release\publish.ps1 -Tag v6.0.2-beta -NoPush

.EXAMPLE
    release\publish.ps1 -Tag v6.0.2 -SkipCreate    # resume a failed run

.NOTES
    Exit codes: 0 done, 1 a step failed (state is reported; resume with
    -SkipCreate), 2 a precondition could not be satisfied ("could not check",
    never a pass). Nothing is ever force-pushed.
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
    [switch] $SkipBuild,
    [switch] $SkipCreate,
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
    try {
        $out = @('protocol=https', 'host=github.com', '') | & git credential fill 2>$null
    }
    catch { return '' }
    foreach ($line in @($out)) {
        if ($line -match '^password=(.+)$') { return $Matches[1] }
    }
    return ''
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Exporter = Join-Path $RepoRoot 'tools\rollout\export_history_repo.ps1'
$GenManifest = Join-Path $PSScriptRoot 'gen_manifest.ps1'
$assetVer = $Tag.Substring(1)
if (-not $AssetsDir) { $AssetsDir = Join-Path $RepoRoot 'Output' }
if (-not $ExportDir) { $ExportDir = Join-Path (Split-Path -Parent $RepoRoot) 'Avro-Keyboard-Publish' }
$ExportDir = [System.IO.Path]::GetFullPath($ExportDir)
$isBeta = $Tag -like '*-beta'

# ---------------------------------------------------------------------------
# 1. Preconditions.
# ---------------------------------------------------------------------------
Write-Step 'Preconditions'

if (-not (Test-Path -LiteralPath $Exporter)) {
    Write-Fail "the history exporter is missing: $Exporter"
    exit 2
}
if (-not (Test-Path -LiteralPath $GenManifest)) {
    Write-Fail "the manifest generator is missing: $GenManifest"
    exit 2
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
Write-Ok 'dev working tree is clean'

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
    Write-Fail 'Bump the project version or fix -Tag; a release that lies about its'
    Write-Fail 'version breaks the updater for every client.'
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
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Fail "missing asset: $path"
        $assetProblem = $true
        continue
    }
    $size = (Get-Item -LiteralPath $path).Length
    if ($size -le 0) {
        Write-Fail "asset is empty: $path"
        $assetProblem = $true
        continue
    }
    $assetPaths[$name] = $path
    Write-Ok ("asset {0} ({1:N1} MB)" -f $name, ($size / 1MB))
}
if ($assetProblem) {
    Write-Fail "expected the four assets in $AssetsDir (built by build-installers.ps1)."
    exit 2
}

$notesBody = $Notes
if ($NotesFile) {
    if (-not (Test-Path -LiteralPath $NotesFile)) {
        Write-Fail "-NotesFile not found: $NotesFile"
        exit 2
    }
    $notesBody = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $NotesFile).Path)
}
if (-not $notesBody) {
    $notesBody = "Avro Keyboard $tagVer release. Installers and portable builds are attached below; the updater feeds are served from this same repository."
}
$prereleaseFlag = $false
if ($isBeta) { $prereleaseFlag = $true }

Write-Ok "release            $Tag -> https://github.com/$Repo ($(if ($isBeta) { 'prerelease' } else { 'stable' }))"
Write-Ok "export scratch     $ExportDir"

if ($WhatIfOnly) {
    Write-Step 'Plan (-WhatIfOnly - nothing created, uploaded, committed or pushed)'
    Write-Info '  1. create the GitHub release (or -SkipCreate: assume it exists)'
    Write-Info '  2. upload the four assets; existing assets are skipped (resumable)'
    Write-Info '  3. HEAD-verify the four public download URLs'
    Write-Info '  4. regenerate updates\versioninfo*.xml from the live releases'
    Write-Info '  5. commit the manifests to dev'
    Write-Info '  6. export_history_repo.ps1: scrubbed-history rewrite + full verification'
    if ($SkipBuild) { Write-Info '     (token-less build of the export: SKIPPED per -SkipBuild)' }
    if ($NoPush) { Write-Info '  7. print the push command; push NOT performed (-NoPush)' }
    else { Write-Info '  7. push the verified rewrite to main (fast-forward)' }
    exit 0
}

$token = Get-GitHubToken
if (-not $token) {
    Write-Fail 'no github.com credential available; the release API needs one.'
    Write-Fail 'Sign in once (Git Credential Manager) or set one up, then re-run.'
    exit 2
}

function Invoke-GitHubApi {
    param([string]$Uri, [string]$Method = 'GET', $Body = $null, [string]$ContentType = 'application/vnd.github+json')
    $headers = @{ 'User-Agent' = 'avro-release-tooling'; 'Accept' = 'application/vnd.github+json'; 'Authorization' = "Bearer $token" }
    $params = @{ Method = $Method; Uri = $Uri; Headers = $headers }
    if ($null -ne $Body) { $params['Body'] = $Body }
    if ($ContentType) { $params['ContentType'] = $ContentType }
    try {
        return Invoke-RestMethod @params
    }
    catch {
        $status = ''
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        throw "GitHub API $Method $Uri failed ($status): $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# 2. Create the release (unless resuming).
# ---------------------------------------------------------------------------
$releaseId = $null
$releaseExists = $false
if ($SkipCreate) {
    Write-Step 'Release (create) - skipped (-SkipCreate)'
    $releaseExists = $true
}
else {
    Write-Step 'Create release'
    $payload = @{
        tag_name         = $Tag
        target_commitish = 'main'
        name             = "Avro Keyboard $assetVer"
        body             = $notesBody
        draft            = $false
        prerelease       = $prereleaseFlag
    }
    try {
        $release = Invoke-GitHubApi -Uri "https://api.github.com/repos/$Repo/releases" -Method 'POST' -Body ($payload | ConvertTo-Json -Depth 4)
        $releaseId = $release.id
        $releaseExists = $true
        Write-Ok "created release $Tag (id $releaseId), tag target main"
    }
    catch {
        $message = $_.Exception.Message
        if ($message -match '\(422\)') {
            Write-Warn "the release $Tag already exists; continuing with it (resume semantics)"
            $releaseExists = $true
        }
        else {
            Write-Fail $message
            Write-Fail 'The release could not be created; nothing was uploaded.'
            exit 1
        }
    }
}

if ($releaseExists -and -not $releaseId) {
    try {
        $release = Invoke-GitHubApi -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag"
        $releaseId = $release.id
        Write-Ok "found existing release $Tag (id $releaseId)"
    }
    catch {
        Write-Fail "could not resolve the existing release $Tag`: $($_.Exception.Message)"
        exit 1
    }
}

# ---------------------------------------------------------------------------
# 3. Upload the assets. Existing names are skipped: re-running after a failure
#    resumes instead of restarting, which is what -SkipCreate is for.
# ---------------------------------------------------------------------------
Write-Step "Upload assets ($releaseId)"
# Same empty-list edge lag as the releases list: an empty answer is legal
# (nothing uploaded yet) but is also what a stale cache returns right after
# an upload - trusting it meant re-uploading files that already exist (422).
# Retry the empty answer a few times; a genuinely empty release pays seconds.
$existingAssets = @()
for ($attempt = 1; $attempt -le 4; $attempt++) {
    try {
        $rawAssets = Invoke-GitHubApi -Uri "https://api.github.com/repos/$Repo/releases/$releaseId/assets?per_page=100"
    }
    catch {
        Write-Fail $_.Exception.Message
        exit 1
    }
    # PowerShell 5.1: an empty JSON array from a function can arrive as one
    # nested empty Object[] element; filter by expected property before any probe.
    $existingAssets = @($rawAssets | Where-Object { $_ -and $_.PSObject.Properties['name'] })
    if ($existingAssets.Count -gt 0 -or $attempt -eq 4) { break }
    Write-Warn "the asset list came back empty (attempt $attempt); retrying in 5s"
    Start-Sleep -Seconds 5
}
$existingNames = @($existingAssets | ForEach-Object { $_.name })
$uploadFailed = $false
foreach ($name in $assets) {
    if ($existingNames -contains $name) {
        Write-Warn "asset already on the release, skipping: $name"
        continue
    }
    $path = $assetPaths[$name]
    try {
        $uploaded = Invoke-RestMethod -Method 'POST' `
            -Uri "https://uploads.github.com/repos/$Repo/releases/$releaseId/assets?name=$name" `
            -Headers @{ 'User-Agent' = 'avro-release-tooling'; 'Accept' = 'application/vnd.github+json'; 'Authorization' = "Bearer $token" } `
            -ContentType 'application/octet-stream' -InFile $path
        Write-Ok "uploaded $name ($($uploaded.size) bytes)"
    }
    catch {
        $status = ''
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        if ($status -eq 422) {
            # Duplicate name: the listing above raced a stale cache. Confirm
            # the asset really is on the release before calling this a failure.
            try {
                $recheck = @(Invoke-GitHubApi -Uri "https://api.github.com/repos/$Repo/releases/$releaseId/assets?per_page=100")
                $recheckNames = @($recheck | Where-Object { $_ -and $_.PSObject.Properties['name'] } | ForEach-Object { $_.name })
                if ($recheckNames -contains $name) {
                    Write-Warn "asset already on the release, skipping: $name"
                    continue
                }
            }
            catch { }
        }
        Write-Fail "upload failed for $name ($status): $($_.Exception.Message)"
        $uploadFailed = $true
    }
}
if ($uploadFailed) {
    Write-Fail 'Not every asset is on the release. Fix the cause and resume with -SkipCreate;'
    Write-Fail 'assets already uploaded are not re-uploaded.'
    exit 1
}

# ---------------------------------------------------------------------------
# 4. HEAD-verify the public URLs. A release the clients cannot download is not
#    a release; retry to absorb CDN lag, then refuse.
# ---------------------------------------------------------------------------
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
        catch {
            if ($attempt -lt 6) { Start-Sleep -Seconds 5 }
        }
    }
    if ($ok) { Write-Ok "reachable  $name" }
    else {
        Write-Fail "not reachable after 6 attempts: $url"
        $verifyFailed = $true
    }
}
if ($verifyFailed) {
    Write-Fail 'The release exists but some downloads do not answer; the manifests were NOT'
    Write-Fail 'touched. Investigate, then resume with -SkipCreate.'
    exit 1
}

# ---------------------------------------------------------------------------
# 5. Regenerate and commit the manifests on dev.
# ---------------------------------------------------------------------------
Write-Step 'Update feeds (updates\versioninfo*.xml)'
& powershell -NoProfile -ExecutionPolicy Bypass -File $GenManifest -Repo $Repo
if ($LASTEXITCODE -ne 0) {
    Write-Fail "gen_manifest.ps1 failed (exit $LASTEXITCODE); the manifests were not committed."
    exit $LASTEXITCODE
}
$add = Invoke-Git -RepoPath $RepoRoot -GitArgs @('add', '--', 'updates/versioninfo.xml', 'updates/versioninfo_beta.xml')
if ($add.Code -ne 0) {
    Write-Fail 'git add of the manifests failed:'
    $add.Output | ForEach-Object { Write-Host "        $_" }
    exit 1
}
$staged = Invoke-Git -RepoPath $RepoRoot -GitArgs @('diff', '--cached', '--quiet')
if ($staged.Code -eq 0) {
    Write-Warn 'the manifests already match the live releases; nothing to commit'
}
else {
    $commit = Invoke-Git -RepoPath $RepoRoot -GitArgs @('commit', '--quiet', '-m', "chore(release): write $Tag update manifests")
    if ($commit.Code -ne 0) {
        Write-Fail 'committing the manifests failed:'
        $commit.Output | ForEach-Object { Write-Host "        $_" }
        exit 1
    }
    Write-Ok "manifests committed to dev (chore(release): write $Tag update manifests)"
}

# ---------------------------------------------------------------------------
# 6. Export: scrubbed-history rewrite, fully verified.
# ---------------------------------------------------------------------------
Write-Step 'History export (scrub + withhold + verify)'
$exportArgs = @('-OutDir', $ExportDir, '-Force')
if ($SkipBuild) { $exportArgs += '-SkipBuild' }
& powershell -NoProfile -ExecutionPolicy Bypass -File $Exporter @exportArgs
$exportRc = $LASTEXITCODE
if ($exportRc -eq 1) {
    Write-Fail 'the export failed verification; see above. Nothing was pushed.'
    exit 1
}
if ($exportRc -ne 0) {
    Write-Fail "the exporter could not run (exit $exportRc): 'could not check', which is never a pass."
    exit 2
}

# ---------------------------------------------------------------------------
# 7. Push the verified fast-forward, or print it.
# ---------------------------------------------------------------------------
if ($NoPush) {
    Write-Step 'Push: SKIPPED (-NoPush)'
    Write-Info 'The verified export is ready. Push it with:'
    Write-Host ''
    Write-Host "    git -C `"$ExportDir`" push https://github.com/$Repo.git main:main"
    Write-Host ''
    exit 0
}

Write-Step 'Push to main'
& git -C $ExportDir push "https://github.com/$Repo.git" main:main
$pushRc = $LASTEXITCODE
if ($pushRc -ne 0) {
    Write-Fail "the push failed (exit $pushRc). The verified export is still at $ExportDir;"
    Write-Fail 're-running the push by hand after fixing the cause is safe (fast-forward).'
    exit 1
}

Write-Step 'Released'
Write-Info "  release   https://github.com/$Repo/releases/tag/$Tag"
Write-Info "  stable    https://raw.githubusercontent.com/$Repo/main/updates/versioninfo.xml"
Write-Info "  beta      https://raw.githubusercontent.com/$Repo/main/updates/versioninfo_beta.xml"
exit 0
