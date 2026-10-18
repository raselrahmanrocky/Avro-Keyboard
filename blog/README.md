# The blog

Posts on this site are plain markdown files in this folder. There is no CMS
and no login form: the repository's own write permission is the only gate, so
whoever can push to this branch can publish, and nobody else can.

## Publishing a post

1. Add a new `.md` file here. The file name becomes the post's slug
   (`blog.html?post=<slug>`), so keep it short, latin and kebab-case
   (`new-ansi-engine.md`).
2. Start the file with a front-matter block (template below).
3. Commit it. The `blog-index` GitHub Action runs on its own and rebuilds
   `blog/posts.json`, `data/blog.json` and `feed.xml` — the post appears on
   the site within a minute, no deploy step needed.

Files named `README.md` and files starting with `_` are ignored.

## Front matter

```yaml
---
title: New ANSI and Bijoy engine
date: 2026-10-18
lang: bn
excerpt: One or two sentences shown in the list and the RSS feed.
tags: [engine, guide]
draft: false
---
```

| Key       | Required | Notes                                                  |
| --------- | -------- | ------------------------------------------------------ |
| `title`   | yes      | Plain text. Posts without it are skipped (with a CI warning). |
| `date`    | yes      | `YYYY-MM-DD`. Invalid or missing dates are skipped.    |
| `lang`    | no       | `bn` or `en`. Defaults to `en` with a warning.         |
| `excerpt` | no       | If absent, the first part of the body is used.         |
| `tags`    | no       | Inline list: `[engine, guide]`.                        |
| `updated` | no       | `YYYY-MM-DD`; shows an "Updated:" line.                |
| `draft`   | no       | `true` keeps the file but hides it from list and feed. |
| `author`       | no | Overrides the default author name for this post.       |
| `authorRole`   | no | Role line under an overridden author's name.           |
| `authorAvatar` | no | Photo path for an overridden author (e.g. `img/authors/name.jpg`). |

The byline — photo, name, role, date — comes from the `author` block in
`js/config.js`: change the name, role, photo (`img/authors/raselrahmanrocky.jpg`) or
profile link there once and every post follows, in both languages. If the
photo file is missing the ring falls back to the author's initials, so the
page never shows a broken image. A post that sets `author:` gets exactly
what it writes — no config role, no profile link.

One post is written in one language — there is no translation pairing. Every
card carries a language badge and the list shows the visitor's active
language first.

## Writing notes

- Ordinary markdown works: headings (`##`/`###`), lists, tables, quotes,
  fenced code, links. The rendered page is sanitised, so scripts and event
  handlers in a post are stripped.
- Image and link paths resolve against `blog.html` at the site root, so use
  paths relative to the repo root: `![shot](img/og-cover.jpg)`,
  `[changelog](changelog.html)`.
- Keep the first paragraph meaningful — it doubles as the card text when no
  `excerpt` is given.

## How the pieces fit

- `blog.html` + `js/blog.js` — the page. It reads the live index and post
  bodies from `raw.githubusercontent.com` (same branch), caches them in
  `localStorage`, and falls back to `data/blog.json` bundled with the site.
- `.github/scripts/build-blog-index.mjs` — the parser/writer.
- `.github/workflows/blog-index.yml` — runs the script on every push that
  touches this folder.

You can rebuild locally with `node .github/scripts/build-blog-index.mjs`.
