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

The maintainer release driver. It must be run from a checkout of the PRIVATE
development repository (it commits the manifests to `dev` and then uses that
repository's history-export tooling, which is deliberately not published here):

     1. tag must equal the version in build\Avro Keyboard.exe; the four assets
        must exist in Output\
     2. create the GitHub release (target main; -beta => prerelease)
     3. upload the assets (existing names are skipped, so a failed run resumes)
     4. HEAD-verify the four public download URLs
     5. regenerate and commit updates\versioninfo*.xml on dev
     6. export: rewrite the dev history with the private key material scrubbed
        and maintainer-only paths withheld, then verify the result (leak gate
        over tree and history, file-by-file tree equality, token-less builds)
     7. push the verified result to main - always a fast-forward, never a
        force-push

```powershell
release\publish.ps1 -Tag v6.0.2 -NotesFile notes.md
release\publish.ps1 -Tag v6.0.2-beta -NoPush      # everything except the push
release\publish.ps1 -Tag v6.0.2 -SkipCreate       # resume a failed run
```

## Why this file is public

The updater XML schema, the asset naming and the feed locations are facts the
clients depend on; documenting them here keeps the public repository honest
about what it serves. The scripts are published for the same reason - they
contain no key material and no maintainer secrets.
