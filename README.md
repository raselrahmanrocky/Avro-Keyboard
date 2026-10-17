# Avro Keyboard Community Edition — website

This branch (`gh-pages`) holds the static website published at
**https://raselrahmanrocky.github.io/Avro-Keyboard/**.

It is a plain, dependency-free static site: no build step, no framework, no
package manager. Edit a file, commit, and it is live.

## What the site does

It presents **Avro Keyboard Community Edition** — an independent continuation of
the open-source Avro Keyboard codebase (MPL-2.0) — and, most importantly, sets
out what was wrong with the official 5.6.0 release and what this project fixed,
feature by feature.

Everything factual about the project is fetched live from the public GitHub API
for [`raselrahmanrocky/Avro-Keyboard`](https://github.com/raselrahmanrocky/Avro-Keyboard)
and the archived upstream baseline. Nothing is hardcoded and no number is
invented:

| Shown on the site | Comes from |
| --- | --- |
| Total commits | `GET /repos/:o/:r/commits?per_page=1`, read from the `Link` header's `rel="last"` page |
| Stars, forks, watchers, open issues, last push | `GET /repos/:o/:r` |
| Contributors | `GET /repos/:o/:r/contributors` |
| "Ahead of the official baseline" | `GET /repos/:o/:r/compare/official...main` |
| Release cards and changelog | `GET /repos/:o/:r/releases` |
| Official 5.6.0 comparison baseline | `GET /repos/mugli/Avro-Keyboard` (archived upstream) |
| Commit-derived changelog for a release with no notes | `GET /repos/:o/:r/commits` or `/compare/{prev}...{tag}` |

## Structure

```
index.html          main page: hero, live stats, official-vs-CE comparison,
                    features, install steps, release cards, download CTA
changelog.html      every release's changelog, deep-linkable (#v6.0.2-beta)
privacy.html        privacy policy for the site and the desktop app
css/                fonts.css (local @font-face), style.css (core),
                    pages.css (changelog + privacy + markdown prose)
js/                 config.js   repositories, cache policy, card summaries
                    i18n.js     English/Bangla dictionary, locale switching,
                                Intl number + date formatting
                    snapshot.js persistent write-through snapshot store
                    github.js   API client: TTL cache, in-flight de-duplication,
                                snapshot fallback, Link-header parsing,
                                retired-link rewriting
                    stats.js    live counter strip
                    audit.js    official-vs-Community-Edition comparison cards
                    releases.js release card grid + filters
                    changelog.js changelog rendering (markdown + sanitiser)
                    privacy.js  table-of-contents scroll-spy on the privacy page
                    theme.js    light/dark toggle: first visits start light,
                                a saved dark choice is reapplied before paint
                    ahead-note.js the shared "commits ahead" figure
                    vendor/     marked + DOMPurify (vendored, no CDN)
data/               repo.json, releases.json, official.json — the committed
                    snapshots the pages paint from before the live refresh
fonts/              self-hosted Manrope (variable) + Hind Siliguri (WOFF2,
                    latin + bengali)
                    with fonts/LICENSE.txt (SIL OFL 1.1)
img/                logo, favicons, splash-screen.webp (+ jpg fallback),
                    og-cover.jpg
_config.yml         informational only — `.nojekyll` disables Jekyll
robots.txt, sitemap.xml
```

Icons are an inline SVG sprite at the top of each page's `<body>` rather than an
external `img/icons.svg`. Referencing an external sprite cannot reliably inherit
`currentColor`, which is what lets every icon take its colour from the element
that uses it; inlining also avoids a request.

## How the data loading works

Data resolves in three layers, each labelled on screen so a visitor always
knows which one they are looking at:

1. **Committed snapshots** (`data/*.json`) — painted first, in the same request
   as the page, so nothing is ever blank.
2. **Saved snapshot** (`localStorage`, `avro-snap-v1`) — every successful API
   response is written through here immediately, so a returning visitor sees
   their own *real* recent numbers even while GitHub is down.
3. **Live GitHub API** — attempted last; on success it paints over the earlier
   layers, updates the saved snapshot, and the status line switches to
   "live". On failure — offline, an outage, or the anonymous rate limit (60
   requests/hour per visitor IP) — the saved or bundled data stays on screen
   with an honest "saved snapshot from …" note.

Responses are cached in `localStorage` (`avro-gh-v1`, ~10 min TTL) and
concurrent requests for the same URL are de-duplicated, so a warm page load
costs one API call rather than six.

To refresh the committed snapshots by hand, copy the JSON from the equivalent
API endpoint and trim each release to the fields `js/github.js` reads
(`tag_name`, `name`, `html_url`, `published_at`, `prerelease`, `draft`, `body`,
`assets[]`).

## Languages (i18n)

The site ships in **English (default)** and **বাংলা**. There is no third-party
localisation library and no build step:

- Every user-visible string carries a `data-i18n="key"` (plus `data-i18n-aria-label`
  and friends); the dictionary lives in `js/i18n.js`.
- Numbers, dates and relative times go through `Intl` formatters from
  `js/i18n.js`, so they follow the active locale.
- The choice is persisted (`localStorage`, `avro-lang`), survives reloads, and
can be deep-linked with `?lang=bn`.
- A tiny inline script in each `<head>` applies the saved language *before*
  first paint, so a Bangla reader never sees English flash past.
- JS-rendered content (counters, comparison cards, release grid, changelog)
  re-renders on the `avro:locale` event — switching language re-formats
  timestamps and plurals too, with no reload.
- To add a language: add its tag to the `langs` table and a dictionary entry
  per key in `js/i18n.js`, then add a button to the header switcher.

## Theme

Light is the default: a first-time visitor always starts on the light palette.
The moon button in the topbar switches to the dark palette, and the choice is
persisted (`localStorage`, `avro-theme`). A tiny inline script in each `<head>`
reapplies a saved dark choice *before* first paint so the palette never flashes
the wrong way, and `js/theme.js` keeps the button's icon, labels and
`aria-pressed` state in sync (labels follow the active language).

## Local development

Any static server works:

```bash
python -m http.server 8080
# then open http://localhost:8080/
```

On loopback only, the API host can be redirected for testing with
`?apiBase=…` (for example a local fixture server). Off loopback the parameter is
ignored, so a crafted link can never repoint a real visitor's requests.

## Content rules

- **Never invent a number.** Star counts, download counts and file sizes are
  read from the API. A figure that cannot be verified is left out.
- **Attribute the baseline correctly.** The official GitHub source repository
  was archived on 9 August 2026; the last official *software* release is 5.6.0
  from 27 August 2019.
- **Every claim in the comparison table traces to `Readme.md` or the 6.0.2-beta
  release notes.**
- Retired-repo links inside release notes are rewritten by `js/github.js` so the
  published site can never show a dead link.

## Licence and attribution

Site code: MPL-2.0, matching the project. Bundled fonts are used under the SIL
Open Font License (see `fonts/LICENSE.txt`). `marked` and `DOMPurify` in
`js/vendor/` keep their own licences.

Avro Keyboard Community Edition is an independent continuation and is **not
affiliated with OmicronLab**. The original Avro Keyboard source and copyright
belong to OmicronLab (Mehdi Hasan Khan).
