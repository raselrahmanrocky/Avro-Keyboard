# Releases and update feeds

Everything a client needs is served from THIS repository:

| What | Where |
| --- | --- |
| Stable update feed | `https://raw.githubusercontent.com/raselrahmanrocky/Avro-Keyboard/main/updates/versioninfo.xml` |
| Beta update feed | `https://raw.githubusercontent.com/raselrahmanrocky/Avro-Keyboard/main/updates/versioninfo_beta.xml` |
| Release assets | `https://github.com/raselrahmanrocky/Avro-Keyboard/releases/download/<tag>/<name>` |
| Changelog / release page | `https://github.com/raselrahmanrocky/Avro-Keyboard/releases/tag/<tag>` |

Asset names carried by every release:

    AvroKeyboard-<version>-win32-setup.exe
    AvroKeyboard-<version>-win64-setup.exe
    AvroKeyboard-<version>-win32-portable.zip
    AvroKeyboard-<version>-win64-portable.zip

`<version>` is the tag without the leading `v`; a `-beta` tag is published as a
GitHub prerelease and updates the beta feed only.

## The scripts here

### `gen_manifest.ps1`

A pure generator: it reads the releases of this repository from the GitHub REST
API and writes `updates\versioninfo.xml` (newest stable release) and
`updates\versioninfo_beta.xml` (newest beta release; falls back to the stable
release when no beta exists, and the XML still reports the release's own
channel). With no releases at all it writes the 6.0.0.0 baseline so the feed
never 404s.

```powershell
release\gen_manifest.ps1              # writes updates\versioninfo*.xml
release\gen_manifest.ps1 -WhatIfOnly  # print the manifests, write nothing
```

It uses the token Git Credential Manager already holds for github.com when one
is available, and works unauthenticated (rate-limited) otherwise. The XML is
written UTF-8 WITH BOM / CRLF, matching what the clients have always parsed.

### `publish.ps1`

The maintainer release driver. It must be run from a checkout of the **PRIVATE**
development repository: it reads the private tree, commits the regenerated
feeds to `dev`, and appends a verified snapshot to the public `main`.

The routine flow is two commands:

```powershell
# 1. build the four assets into Output\
.\tools\release\build-installers.ps1

# 2. publish
.\release\publish.ps1 -Tag v6.0.2 -NotesFile release-notes.md `
    -InnoExtract C:\Avro-Public-Reset\tools\innoextract-1.12-dev\innoextract.exe
```

### `-SourceOnly`: append the source without cutting a release

When only the source mirror has to move forward, the same driver runs the same
gates but stops after the push:

```powershell
.\release\publish.ps1 -SourceOnly
.\release\publish.ps1 -SourceOnly -WhatIfOnly   # every local gate, nothing pushed
```

`-Tag` is optional in this mode; the run labels the snapshot with today's date.
There is no tag, no release, no uploaded asset and no feed regeneration: the
snapshot's tree is applied to a fresh clone of the public `main`, committed on
top of it with a message that says exactly that, gated again (tree scan and
main-scoped history scan) and pushed as a fast-forward. The asset gate is the
only step that does not run, because no asset is built or uploaded.

`-InnoExtract` is not optional in practice: the setup assets are built with
**Inno Setup 6.7**, and `innoextract` 1.9 (the winget build) cannot read them.
The build in use is pinned by SHA-256 in
[../docs/ROLLOUT_STATUS.md](../docs/ROLLOUT_STATUS.md) and must live outside
the repository. See [../docs/DECISIONS.md](../docs/DECISIONS.md) D6.

What one run does, in order:

 1. **the asset gate** — every asset is extracted (a portable ZIP in memory, an
    installer with `innoextract`) and every extracted file is scanned for the
    raw IKM, for the masked IKM (allowed only in the extracted app-root keyboard
    executable) and for plaintext `Ansi V*.json` mappings;
 2. **the verified snapshot** — one commit of the private tree with the
    maintainer-only paths withheld, gated by the leak gate over the tree *and*
    over every reachable object, and built token-less for Win32 and Win64;
 3. **a fresh clone of the public repository**, so nothing of an old clone's
    history can travel with it;
 4. `read-tree --reset -u` — the snapshot's tree is applied to that clone;
 5. **a commit on top of the public `main`** — the public history is appended
    to, never rewritten;
 6. **the gates on the public clone**: the tree scan, and a history scan scoped
    to `main`;
 7. **a fast-forward push** — never a force-push;
 8. the release is created **at that commit**, the gated assets are uploaded,
    and the four download URLs are HEAD-verified;
 9. the feeds are regenerated and committed to the public `main` and to `dev`.

```powershell
release\publish.ps1 -Tag v6.0.2 -NotesFile notes.md
release\publish.ps1 -Tag v6.0.2-beta -NoPush        # everything except the push
release\publish.ps1 -Tag v6.0.2 -WhatIfOnly        # every local gate, no writes
release\publish.ps1 -Tag v6.0.2 -SkipCreate         # resume a failed run
```

#### What a publish costs, and what it may not do

- **About 165 seconds** of extra time: the main-scoped history gate now sweeps
  the whole published history (398 commits, roughly 120 MB), because the public
  `main` is a history rather than a single commit. It is the price of
  publishing into a history, and it is why a publish is a deliberate act.
- **The asset gate is mandatory.** An asset that cannot be extracted, or that
  carries the raw IKM, the masked IKM outside the app-root keyboard executable,
  or a plaintext mapping, is **dropped** - it is never uploaded. The run stops
  rather than continuing, unless `-AllowDroppedAssets` is given. With that flag
  the dropped asset is simply not uploaded, so **the release body must name
  it**: a body that advertises a download which does not exist is worse than a
  missing one. The section is appended **automatically** - the publish flow
  writes it, with the gate's own reason, and does not leave it to the
  maintainer to remember - and the feed generator skips any asset the release
  does not carry, so no feed advertises a URL that would 404. A dropped asset
  is withheld from the upload **and** from the download-URL verification, not
  merely named in the body: it is not shipped, and its URL is expected not to
  exist.
- **No force-push, ever.** The public history is append-only, and the two
  one-time rewrites of 2026-10-21 spent the only exception
  ([../docs/DECISIONS.md](../docs/DECISIONS.md) D1, D2).
- **The release id is preserved.** A tag move re-points the release with a
  PATCH; it never deletes and recreates it
  ([../docs/DECISIONS.md](../docs/DECISIONS.md) D4).

## Why this file is public

The updater XML schema, the asset naming and the feed locations are facts the
clients depend on; documenting them here keeps the public repository honest
about what it serves. The scripts are published for the same reason - they
contain no key material and no maintainer secrets.
