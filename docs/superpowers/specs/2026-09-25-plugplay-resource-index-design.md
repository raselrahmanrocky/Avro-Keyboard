# Plug & Play Resource Catalog — Design Spec

**Date:** 2026-09-25
**Status:** Approved (sections A-D reviewed and approved by user)
**Repos involved:** `raselrahmanrocky/Avro-Keyboard-Resource` (resource repo), `Avro-Keyboard` (main repo)

## 1. Goal

Adding any file to the Avro-Keyboard-Resource repo — via GitHub web UI or git push —
must make it appear in Avro Keyboard's **Download Resources** section automatically,
with zero manual `index.json` maintenance. Full plug & play.

## 2. Decisions (from clarification rounds)

1. **New top-level folder** in the repo becomes a new category in the app;
   files in the existing five folders also work (both, option g).
2. **Only the five known types exist for now** (`.avrolayout`, `.ttf/.otf`,
   `.avroskin`, `.AvroEnco`, `.pdf/.htm/.html`). Other extensions are skipped and
   logged; installer code is upgraded later if new types ever ship (option kh).
3. **Automation = GitHub Actions primary + local script fallback** (option g):
   push triggers index regeneration; the same script can be run by hand.
4. **Descriptions:** English only; `descriptionBn`/`titleBn` fields are removed
   from future index output. Existing hand-written English descriptions are
   preserved forever (smart merge). Optional `<name>.meta.json` sidecar takes
   priority when present (option g).

## 3. Architecture (Section A)

```
push (web or git) -> resource repo main
       -> GitHub Actions: update-index.yml
       -> runs .github/scripts/generate-index.ps1
       -> index.json rewritten ONLY if content changed
       -> bot commit + push (no change = no commit = no loop)
app "Download Resources" -> raw.githubusercontent index.json -> shows new file
```

- **Source of truth = the repo's own folders.** `index.json` is a derived artifact.
- Scanner lives **inside the resource repo** (`.github/scripts/generate-index.ps1`);
  Actions and the local fallback run the identical script.
- Latency: ~1-5 minutes (Actions ~30 s + raw CDN cache up to ~4 min).
- **App side: zero code changes** (see Section D1 proof).

## 4. Scanner rules (Section B)

Per-file metadata precedence, keyed by repo-relative path
(`Skins/Classic.avroskin`, forward slashes):

| Priority | Source | Rule |
|---|---|---|
| 1 | `<basename>.meta.json` sidecar next to the file | Keys present in sidecar override (`description`, `version` — both optional) |
| 2 | Existing `index.json` entry with the same `file` path | Never lost by a rescan (smart merge) |
| 3 | Filename | Fallback: base name becomes the English description; no version |

- Sidecar schema: `{"description": "...", "version": "..."}` (English only).
  The sidecar itself never appears in the catalog (`.json` not whitelisted).
- Known limitation: renaming a file changes its merge key, so its description
  falls back to the filename unless a sidecar is added (accepted).
- Categories: every top-level directory except `.hidden`, `licenses`, and root
  files. Known folder order first (`AnsiMapping, KeyboardLayouts, Fonts, Skins,
  Docs`), unknown folders appended alphabetically. Titles: pretty names for the
  known five, folder name for new ones. Empty categories (no whitelisted file)
  are omitted. Category `id` = lowercased alphanumeric slug of the folder name.
- Item type by extension (case-insensitive): `.avrolayout`->layout,
  `.ttf`/`.otf`->font, `.avroskin`->skin, `.avroenco`->ansimapping,
  `.pdf`/`.htm`/`.html`->doc. Any other extension: skipped + logged.
- Recursive scan inside category folders (e.g. `Docs/images` — images are not
  whitelisted, so they never appear as items). Files sorted by relative path for
  stable output.
- Output: `schema: 1`, `generated` (yyyy-MM-dd), `repo`, `branch: main`,
  `categories[].items[] = {file, name, type, description, size, sha256[, version]}`.
  UTF-8 **without BOM**. `descriptionBn`/`titleBn` no longer written.
- **No-op detection:** the new core JSON (everything except `generated`) is
  compared against the old file round-tripped through the same engine's
  `ConvertTo-Json`. Identical -> file left completely untouched (date does not
  churn, bot never commits).
- SHA-256 is computed from the checked-out bytes; `.gitattributes` (`* -text`)
  guarantees checkout bytes == committed bytes == raw-served bytes.

## 5. GitHub Actions (Section C1)

`.github/workflows/update-index.yml` in the resource repo:

- Trigger: `push` to `main` with `paths-ignore: index.json, README.md, LICENSE,
  licenses/**, .github/**` (bot commit and workflow edits never self-trigger),
  plus `workflow_dispatch` for a manual Run button.
- `permissions: contents: write`; `concurrency: update-index` (serialized runs).
- Steps: checkout -> run scanner (`shell: pwsh`) -> commit/push `index.json`
  **only if `git diff --quiet` reports a change** (message
  `chore: regenerate index.json [skip ci]`, committed as `avro-index-bot`).
- Loop safety in two layers: no-op runs never change the file, and pushes made
  with the built-in `GITHUB_TOKEN` never re-trigger workflows.
- Failure handling: scanner/workflow error -> index untouched -> app keeps
  serving the previous catalog (nothing breaks).
- Note: if branch protection is ever enabled on `main`, the bot needs an
  allowance to push.

## 6. Old mirror script (Section C2)

`tools/resource-sync/generate-resource-index.ps1` (main repo) is **kept, not
deleted**, with responsibilities split:

1. **Index generation removed entirely** — the resource-repo scanner becomes the
   single source of index logic. The mirror script *delegates*: after copying it
   invokes `.github/scripts/generate-index.ps1` inside the target repo.
2. **Mirror stays** (assets\ -> five category folders) but now shows a loud
   warning + interactive `Continue? [y/N]` prompt before wiping, because files
   added directly to those five folders and absent from `assets\` are deleted
   (`-Force` switch for non-interactive use).
3. ANSI metadata parity: while mirroring, a `*.json Metadata` sidecar in assets
   is converted to a `<base>.meta.json` next to the copied `.AvroEnco`, so the
   scanner keeps producing rich descriptions for future ANSI additions.

## 7. App-side confirmation (Section D1) — no code changes

- `clsResourceCatalog.pas:73` fetch URL unchanged; `JsonStr` returns `''` for
  missing `descriptionBn`/`titleBn` (:245, :265) -> parsing unaffected.
- `ufrmResourceBrowser.pas:306` already guards `DescriptionBn <> ''` -> Bangla
  line simply stops appearing (desired).
- `uResourceInstaller.pas:72-81` handles all five types; scanner whitelist ==
  installer type set -> "Unknown resource type" impossible from new files.
- Raw URLs with spaces already work (proven by the Bijoy harness download).

## 8. Testing plan (Section D2)

**Phase 1 — local, no push:**
1. Run scanner on the real repo -> diff must touch ONLY removal of
   `descriptionBn`/`titleBn` (and `generated`); all 35 descriptions/sizes/shas
   byte-identical. Second run -> completely no-op (file untouched).
2. Sidecar test: temp `.avroskin` + `.meta.json` -> sidecar description wins;
   clean up afterwards.
3. New-folder test: temp folder + whitelisted file -> new category appended at
   the end; clean up.
4. Unknown extension (`.txt`) -> not listed, logged.
5. Output: valid JSON, UTF-8 no BOM.
6. Mirror script: warning prompt appears; answering `N` aborts with zero
   deletions; `-Force` path + delegation to scanner works.

**Phase 2 — after the user pushes (integration):**
7. First commit (workflow + scanner) -> run via `workflow_dispatch` -> no-op,
   no junk commit.
8. Real new file push -> bot updates index within ~5 min (sha/size/description).
9. Open app -> new item listed -> Download -> installs; remote sha verified.
10. Replace file -> sha changes in index; delete file -> item disappears.

**Phase 3:** remove test files; run `verification-before-completion` before
claiming done.

## 9. Deliverables

1. Resource repo: `.github/workflows/update-index.yml`,
   `.github/scripts/generate-index.ps1`, README "Adding resources" section.
2. Main repo: `tools/resource-sync/generate-resource-index.ps1` reworked
   (warning prompt, `-Force`, index logic removed, delegates to scanner,
   ANSI metadata -> sidecar).
3. No Avro Keyboard application code changes.
