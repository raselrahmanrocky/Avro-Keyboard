<#
.SYNOPSIS
    Regenerates updates\versioninfo.xml and updates\versioninfo_beta.xml from the
    releases of raselrahmanrocky/Avro-Keyboard.

.DESCRIPTION
    The single-repo successor to the old Avro-Keyboard-Releases manifest job.
    The feed files live under updates\ on the main branch of the SAME repository
    that hosts the release assets, so the client URLs
    (raw.githubusercontent.com/raselrahmanrocky/Avro-Keyboard/main/updates/...)
    always point at one source of truth.

    This script is a pure generator: it only READS the GitHub REST API and writes
    the two XML files. Publishing them (commit, export, push) is publish.ps1's
    job. It never uses the gh CLI; it authenticates with the token Git Credential
    Manager already holds for github.com when one is available, and falls back to
    an unauthenticated (rate-limited) call otherwise.

    Selection rules, preserved from the old generator:
      stable feed  the newest live release that is neither a GitHub prerelease
                   nor tagged *-beta*
      beta feed    the newest live release that IS a prerelease or *-beta*
                   tagged; falls back to the stable release when no beta exists,
                   and the channel node still reports the release's OWN channel
                   ("stable"), so a client is never labelled beta on a stable
                   download
    With no live releases at all, both files get the 6.0.0.0 baseline with an
    empty releasedate, so a fresh clone of the public repository serves a valid
    feed (a user sees "latest version") instead of a 404.

    The XML is written byte-identically in shape to what the live clients have
    been parsing: UTF-8 WITH BOM, CRLF, two-space indent, namedversion last.

.PARAMETER Repo
    The repository whose releases are read. Default: raselrahmanrocky/Avro-Keyboard.

.PARAMETER OutDir
    Directory for the two XML files. Default: <repository root>\updates, resolved
    from this script's location so the result does not depend on the current
    directory. (Relative custom values resolve against the current directory.)

.PARAMETER SkipReportPath
    Write a JSON report of the assets a feed did NOT advertise, because the
    release it points at does not carry them. The publish flow reads it to
    name the skips in the feed commit message, so a client is never told to
    download a file the release does not have.

.PARAMETER WhatIfOnly
    Fetch and compute, print both manifests, write nothing.

.EXAMPLE
    release\gen_manifest.ps1

.EXAMPLE
    release\gen_manifest.ps1 -WhatIfOnly

.NOTES
    Exit codes: 0 written (or WhatIfOnly), 1 refused (a release was found whose
    data cannot be rendered), 2 could not run (network, auth, I/O).
#>
[CmdletBinding()]
param(
    [string] $Repo = 'raselrahmanrocky/Avro-Keyboard',
    [string] $OutDir = '',
    [string] $SkipReportPath = '',
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

$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $RepoRoot 'updates' }

# ---------------------------------------------------------------------------
# Token: reuse what Git Credential Manager already stores for github.com. When
# absent, the API still answers for a public repository - just rate-limited - so
# that is a warning, not a failure.
# ---------------------------------------------------------------------------
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

$token = Get-GitHubToken
if (-not $token) {
    Write-Warn 'no github.com credential found; calling the API unauthenticated (rate-limited)'
}

function Invoke-GitHubApi {
    param([string]$Uri, [string]$Method = 'GET')
    $headers = @{ 'User-Agent' = 'avro-release-tooling'; 'Accept' = 'application/vnd.github+json' }
    if ($token) { $headers['Authorization'] = "Bearer $token" }
    try {
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers
    }
    catch {
        $status = ''
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        throw "GitHub API $Method $Uri failed ($status): $($_.Exception.Message)"
    }
}

# Every asset a feed does not advertise is recorded here, with the reason.
# The feed is generated from the live release, so a skip is a fact about that
# release - usually an asset the asset gate dropped and never uploaded.
$script:SkippedAssets = @()

Write-Step 'Fetch releases'
# The list endpoint can lag behind a release that was JUST created (observed:
# an authenticated list right after the first create returned an empty array),
# and an empty list is indistinguishable from the legitimate zero state - it
# would silently write baseline manifests over a live release. Retry the empty
# answer; a genuinely empty repository merely pays a few seconds.
$releases = @()
for ($attempt = 1; $attempt -le 4; $attempt++) {
    try {
        $rawResponse = Invoke-GitHubApi -Uri "https://api.github.com/repos/$Repo/releases?per_page=100"
    }
    catch {
        Write-Fail $_.Exception.Message
        Write-Fail "'could not check' is never a pass; nothing was written."
        exit 2
    }
    # PowerShell 5.1: an empty JSON array survives the function return as ONE
    # nested empty Object[] element (or null), so a bare $releases.Count reads 1
    # on an empty answer and the loop would break without retrying. Filter by
    # the expected property first, then count what actually remains.
    $releases = @($rawResponse | Where-Object { $_ -and $_.PSObject.Properties['tag_name'] })
    if ($releases.Count -gt 0 -or $attempt -eq 4) { break }
    Write-Warn "the release list came back empty (attempt $attempt); retrying in 5s"
    Start-Sleep -Seconds 5
}
if ($releases.Count -eq 100) {
    Write-Warn 'exactly 100 releases returned (the per_page ceiling); older ones were not listed'
}
$active = @($releases | Where-Object { -not $_.draft })
$active = @($active | Sort-Object -Property @{ Expression = { if ($_.published_at) { [DateTime]$_.published_at } else { [DateTime]::MinValue } }; Descending = $true },
                                          @{ Expression = { $_.id }; Descending = $true })
Write-Ok "$($releases.Count) release(s), $($active.Count) live"

$utf8WithBom = New-Object System.Text.UTF8Encoding($true)

function Write-ManifestFile {
    param([string]$Name, [string]$Content)
    $path = Join-Path $OutDir $Name
    if ($WhatIfOnly) {
        Write-Host ''
        Write-Host "----- $path -----"
        Write-Host $Content
        return
    }
    if (-not (Test-Path -LiteralPath $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($path, $Content, $utf8WithBom)
    Write-Ok "wrote $path"
}

# ---------------------------------------------------------------------------
# Zero state: no live releases. The 6.0.0.0 baseline keeps the feed valid; the
# empty releasedate is deliberate - a live date would churn the file on every
# run - and the client requires the node, so it is kept, not removed.
# ---------------------------------------------------------------------------
if ($active.Count -eq 0) {
    Write-Warn 'no live releases found; writing the 6.0.0.0 baseline manifests'
    $defaultXml = @(
        '<?xml version="1.0" encoding="utf-8"?>',
        '<versioninfo>',
        '  <versionmajor>6</versionmajor>',
        '  <versionminor>0</versionminor>',
        '  <versionrevision>0</versionrevision>',
        '  <versionbuild>0</versionbuild>',
        '  <channel>stable</channel>',
        "  <downloadurl>https://github.com/$Repo</downloadurl>",
        "  <changelogurl>https://github.com/$Repo</changelogurl>",
        "  <productpageurl>https://github.com/$Repo</productpageurl>",
        '  <releasedate></releasedate>',
        '  <namedversion>Avro Keyboard 6.0.0</namedversion>',
        '</versioninfo>'
    ) -join "`r`n"
    Write-ManifestFile -Name 'versioninfo.xml' -Content $defaultXml
    Write-ManifestFile -Name 'versioninfo_beta.xml' -Content $defaultXml
    exit 0
}

# ---------------------------------------------------------------------------
# Classification, with the same fallbacks the old generator used.
# ---------------------------------------------------------------------------
$eval = { param($r) ($r.prerelease -eq $true) -or ($r.tag_name -like '*-beta*') }
$stableRel = $active | Where-Object { -not (& $eval $_) } | Select-Object -First 1
$betaRel   = $active | Where-Object { & $eval $_ } | Select-Object -First 1
if (-not $betaRel) {
    Write-Info 'no beta release found; the beta feed falls back to the stable release'
    $betaRel = $stableRel
}
if (-not $stableRel) {
    Write-Info 'no stable release found; the stable feed falls back to the newest release'
    $stableRel = $active[0]
}

function Generate-ManifestXml {
    param($release)
    if (-not $release) { return $null }

    $tag = $release.tag_name
    $isBeta = & $eval $release
    # The release decides the channel, never the file the XML lands in.
    $channel = if ($isBeta) { 'beta' } else { 'stable' }
    $assets = @($release.assets | Where-Object { $_ -and $_.PSObject.Properties['name'] })

    $setup32 = $assets | Where-Object { $_.name -like '*setup*.exe' -and ($_.name -like '*win32*' -or $_.name -like '*x86*') } | Select-Object -First 1
    $setup64 = $assets | Where-Object { $_.name -like '*setup*.exe' -and ($_.name -like '*win64*' -or $_.name -like '*x64*') } | Select-Object -First 1
    $legacy  = $assets | Where-Object { $_.name -like '*setup*.exe' -or $_.name -like '*.exe' } | Select-Object -First 1
    $portable32 = $assets | Where-Object { $_.name -like '*portable*.zip' -and ($_.name -like '*win32*' -or $_.name -like '*x86*') } | Select-Object -First 1
    $portable64 = $assets | Where-Object { $_.name -like '*portable*.zip' -and ($_.name -like '*win64*' -or $_.name -like '*x64*') } | Select-Object -First 1

    $cleanVer = $tag.TrimStart('v').TrimStart('V')

    # A feed may only advertise an asset THE RELEASE CARRIES. The candidates
    # above are chosen from the release's own asset list, and this pass checks
    # that again before anything is linked: an advertised name that is absent
    # is a 404 the client finds out about at download time, not before.
    # An empty slot is recorded too - that is the case the asset gate creates
    # when an asset is dropped and never uploaded.
    $present = @{}
    foreach ($a in $assets) { $present[[string]$a.name] = $true }
    $slots = [ordered]@{
        setup32    = @{ asset = $setup32;    expected = "AvroKeyboard-$cleanVer-win32-setup.exe" }
        setup64    = @{ asset = $setup64;    expected = "AvroKeyboard-$cleanVer-win64-setup.exe" }
        portable32 = @{ asset = $portable32; expected = "AvroKeyboard-$cleanVer-win32-portable.zip" }
        portable64 = @{ asset = $portable64; expected = "AvroKeyboard-$cleanVer-win64-portable.zip" }
    }
    foreach ($key in $slots.Keys) {
        $slot = $slots[$key]
        if (-not $slot.asset) {
            $script:SkippedAssets += [pscustomobject]@{
                release = $tag; slot = $key; asset = $slot.expected
                reason = 'not carried by this release'
            }
            continue
        }
        if (-not $present.ContainsKey([string]$slot.asset.name)) {
            $script:SkippedAssets += [pscustomobject]@{
                release = $tag; slot = $key; asset = [string]$slot.asset.name
                reason = 'not present in the release''s asset list'
            }
            $slot.asset = $null
        }
    }
    $setup32 = $slots['setup32'].asset
    $setup64 = $slots['setup64'].asset
    $portable32 = $slots['portable32'].asset
    $portable64 = $slots['portable64'].asset

    # The main download URL falls back to any .exe the release carries. That is
    # a real asset, so it is not a 404 - but if the expected win64 setup is the
    # thing that is missing, the fallback is the reason the feed is not
    # offering what a client would expect, and it is recorded.
    if (-not $setup64 -and $legacy) {
        $script:SkippedAssets += [pscustomobject]@{
            release = $tag; slot = 'downloadurl'; asset = [string]$legacy.name
            reason = 'the release does not carry the expected win64 setup; the feed falls back to this asset for the main download URL'
        }
    }

    $downloadUrl = if ($setup64) { "https://github.com/$Repo/releases/download/$tag/$($setup64.name)" }
    elseif ($legacy) { "https://github.com/$Repo/releases/download/$tag/$($legacy.name)" }
    else { "https://github.com/$Repo/releases/tag/$tag" }
    $downloadUrl32 = if ($setup32) { "https://github.com/$Repo/releases/download/$tag/$($setup32.name)" } else { $null }
    $downloadUrl64 = if ($setup64) { "https://github.com/$Repo/releases/download/$tag/$($setup64.name)" } else { $null }
    $portableUrl32 = if ($portable32) { "https://github.com/$Repo/releases/download/$tag/$($portable32.name)" } else { $null }
    $portableUrl64 = if ($portable64) { "https://github.com/$Repo/releases/download/$tag/$($portable64.name)" } else { $null }

    $numOnly = ($cleanVer -split '-')[0]
    $parts = $numOnly.Split('.')
    $major = if ($parts.Length -gt 0 -and $parts[0] -ne '') { $parts[0] } else { '6' }
    $minor = if ($parts.Length -gt 1 -and $parts[1] -ne '') { $parts[1] } else { '0' }
    $rev   = if ($parts.Length -gt 2 -and $parts[2] -ne '') { $parts[2] } else { '0' }
    $build = if ($parts.Length -gt 3 -and $parts[3] -ne '') { $parts[3] } else { '0' }

    $date = if ($release.published_at) { ([DateTime]$release.published_at).ToString('yyyy-MM-dd') } else { '' }

    $xmlLines = @(
        '<?xml version="1.0" encoding="utf-8"?>',
        '<versioninfo>',
        "  <versionmajor>$major</versionmajor>",
        "  <versionminor>$minor</versionminor>",
        "  <versionrevision>$rev</versionrevision>",
        "  <versionbuild>$build</versionbuild>",
        "  <channel>$channel</channel>",
        "  <downloadurl>$downloadUrl</downloadurl>"
    )
    if ($downloadUrl32) { $xmlLines += "  <downloadurl32>$downloadUrl32</downloadurl32>" }
    if ($downloadUrl64) { $xmlLines += "  <downloadurl64>$downloadUrl64</downloadurl64>" }
    if ($portableUrl32) { $xmlLines += "  <downloadurlportable32>$portableUrl32</downloadurlportable32>" }
    if ($portableUrl64) { $xmlLines += "  <downloadurlportable64>$portableUrl64</downloadurlportable64>" }
    $xmlLines += @(
        "  <changelogurl>https://github.com/$Repo/releases/tag/$tag</changelogurl>",
        "  <productpageurl>https://github.com/$Repo</productpageurl>",
        "  <releasedate>$date</releasedate>",
        "  <namedversion>Avro Keyboard $cleanVer</namedversion>",
        '</versioninfo>'
    )
    return ($xmlLines -join "`r`n")
}

Write-Step 'Generate'
$stableXml = Generate-ManifestXml $stableRel
$betaXml   = Generate-ManifestXml $betaRel
if (-not $stableXml -or -not $betaXml) {
    Write-Fail 'a live release was selected but its manifest could not be rendered.'
    exit 1
}
Write-Ok "stable feed <- $($stableRel.tag_name)"
Write-Ok "beta feed   <- $($betaRel.tag_name)"
Write-ManifestFile -Name 'versioninfo.xml' -Content $stableXml
Write-ManifestFile -Name 'versioninfo_beta.xml' -Content $betaXml

if ($script:SkippedAssets.Count -gt 0) {
    Write-Warn ("{0} asset(s) are not advertised by the feed(s):" -f $script:SkippedAssets.Count)
    foreach ($s in $script:SkippedAssets) {
        Write-Warn ("  {0}: {1} ({2})" -f $s.slot, $s.asset, $s.reason)
    }
}
else {
    Write-Ok 'every advertised asset is present in the release it points at'
}

if ($SkipReportPath) {
    $reportFull = [System.IO.Path]::GetFullPath($SkipReportPath)
    $reportDir = Split-Path -Parent $reportFull
    if ($reportDir -and -not (Test-Path -LiteralPath $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    # The beta feed falls back to the stable release when there is no beta, so
    # the same skip can be reached twice. Report each one once.
    $unique = @()
    foreach ($s in @($script:SkippedAssets)) {
        $key = "$($s.release)|$($s.slot)|$($s.asset)"
        if (-not ($unique | Where-Object { $_.'key' -eq $key })) {
            $unique += [pscustomobject]@{ key = $key; entry = $s }
        }
    }
    $skippedOut = @($unique | ForEach-Object { $_.entry })
    $payload = [ordered]@{
        release = $Repo
        skipped = $skippedOut
        count   = $skippedOut.Count
    }
    $payload | ConvertTo-Json -Depth 5 | ForEach-Object {
        [System.IO.File]::WriteAllText($reportFull, $_, (New-Object System.Text.UTF8Encoding($false)))
    }
    Write-Ok "skip report      $reportFull"
}

exit 0
