#!/usr/bin/env node
/* ==========================================================================
   Rebuilds the blog index from the markdown files in blog/.

   Run by .github/workflows/blog-index.yml on every push to the published
   branch that touches blog/ — and runnable by hand:

       node .github/scripts/build-blog-index.mjs

   Writes three files, all committed back by the workflow:
     blog/posts.json   the index the page reads from raw.githubusercontent.com
     data/blog.json    the same index bundled with the site as a fallback
     feed.xml          an RSS 2.0 feed of the same posts

   Front matter is deliberately simple (see blog/README.md):
     title, date (YYYY-MM-DD), lang (bn|en), excerpt, tags [a, b],
     updated (YYYY-MM-DD), draft (true|false)
   ========================================================================== */

import { readdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const ROOT = fileURLToPath(new URL('../..', import.meta.url));
const BLOG_DIR = path.join(ROOT, 'blog');
const DATA_DIR = path.join(ROOT, 'data');

const SITE = 'https://raselrahmanrocky.github.io/Avro-Keyboard';
const FEED_TITLE = 'Avro Keyboard Community Edition — Blog';
const FEED_DESC =
  'Development notes, guides and announcements from the Avro Keyboard Community Edition project.';

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const SLUG_RE = /^[a-z0-9][a-z0-9-]*$/;
const LANGS = ['en', 'bn'];
const EXCERPT_LIMIT = 220;

const warnings = [];
const warn = (message) => { warnings.push(message); };

/* ------------------------------------------------------------ front matter */
function unquote(value) {
  const text = String(value).trim();
  if (text.length > 1 &&
      ((text.startsWith('"') && text.endsWith('"')) ||
       (text.startsWith("'") && text.endsWith("'")))) {
    return text.slice(1, -1).trim();
  }
  return text;
}

function parseTags(value) {
  const inner = String(value).trim().replace(/^\[/, '').replace(/\]$/, '');
  return inner.split(',').map(unquote).filter(Boolean);
}

function parseFrontMatter(source, label) {
  /* A BOM (Notepad and friends add one on Windows) must not hide the --- */
  const text = String(source).replace(/^\uFEFF/, '');
  const match = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?/.exec(text);
  if (!match) {
    warn(`${label}: no front-matter block; skipping`);
    return null;
  }

  const meta = {};
  for (const line of match[1].split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const at = trimmed.indexOf(':');
    if (at === -1) continue;
    const key = trimmed.slice(0, at).trim().toLowerCase();
    const raw = trimmed.slice(at + 1);
    if (key === 'tags') meta.tags = parseTags(raw);
    else if (key === 'draft') meta.draft = /^true$/i.test(unquote(raw));
    else meta[key] = unquote(raw);
  }
  return { meta, body: text.slice(match[0].length) };
}

/* ----------------------------------------------------------------- excerpt */
function deriveExcerpt(body) {
  const plain = String(body)
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`[^`]*`/g, ' ')
    .replace(/!\[[^\]]*\]\([^)]*\)/g, ' ')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .replace(/^#{1,6}\s+/gm, '')
    .replace(/[*_>~#]+/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  if (plain.length <= EXCERPT_LIMIT) return plain;
  const cut = plain.slice(0, EXCERPT_LIMIT);
  const at = cut.lastIndexOf(' ');
  return (at > EXCERPT_LIMIT / 2 ? cut.slice(0, at) : cut).trim() + '…';
}

/* ---------------------------------------------------------------- collect -- */
async function collectPosts() {
  const entries = await readdir(BLOG_DIR, { withFileTypes: true });
  const posts = [];

  for (const entry of entries) {
    if (!entry.isFile()) continue;
    const name = entry.name;
    if (!/\.md$/i.test(name)) continue;
    if (/^readme\.md$/i.test(name) || name.startsWith('_')) continue;

    const label = `blog/${name}`;
    const slug = name.replace(/\.md$/i, '');
    if (!SLUG_RE.test(slug)) {
      warn(`${label}: file name must be latin kebab-case; skipping`);
      continue;
    }

    const source = await readFile(path.join(BLOG_DIR, name), 'utf8');
    const parsed = parseFrontMatter(source, label);
    if (!parsed) continue;
    const { meta, body } = parsed;

    if (meta.draft === true) continue;

    const title = meta.title || '';
    if (!title) {
      warn(`${label}: missing "title"; skipping`);
      continue;
    }

    if (!DATE_RE.test(meta.date || '')) {
      warn(`${label}: "date" must be YYYY-MM-DD; skipping`);
      continue;
    }

    let lang = (meta.lang || '').toLowerCase();
    if (!lang) {
      lang = 'en';
      warn(`${label}: "lang" missing; defaulting to en`);
    }
    if (!LANGS.includes(lang)) {
      warn(`${label}: "lang" must be one of ${LANGS.join(', ')}; skipping`);
      continue;
    }

    const post = {
      slug,
      file: name,
      title,
      date: meta.date,
      lang,
      excerpt: meta.excerpt || deriveExcerpt(body),
      tags: meta.tags || []
    };
    if (DATE_RE.test(meta.updated || '')) post.updated = meta.updated;
    /* Author overrides stay out of the index entirely when absent so the
       page always falls back to the config's default author. */
    if (meta.author) post.author = meta.author;
    if (meta.authorrole) post.authorRole = meta.authorrole;
    if (meta.authoravatar) post.authorAvatar = meta.authoravatar;
    posts.push(post);
  }

  posts.sort((a, b) =>
    String(b.date).localeCompare(String(a.date)) || a.slug.localeCompare(b.slug));
  return posts;
}

/* ------------------------------------------------------------------- feed -- */
const xmlEscape = (value) => String(value)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&apos;');

const cdata = (value) =>
  '<![CDATA[' + String(value).replace(/]]>/g, ']]]]><![CDATA[>') + ']]>';

function buildFeed(posts) {
  const items = posts.map((post) => {
    const url = `${SITE}/blog.html?post=${encodeURIComponent(post.slug)}`;
    const pubDate = new Date(`${post.date}T00:00:00Z`).toUTCString();
    return [
      '    <item>',
      `      <title>${xmlEscape(post.title)}</title>`,
      `      <link>${url}</link>`,
      `      <guid isPermaLink="true">${url}</guid>`,
      `      <pubDate>${pubDate}</pubDate>`,
      `      <description>${cdata(post.excerpt)}</description>`,
      '    </item>'
    ].join('\n');
  }).join('\n');

  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<rss version="2.0">',
    '  <channel>',
    `    <title>${xmlEscape(FEED_TITLE)}</title>`,
    `    <link>${SITE}/blog.html</link>`,
    `    <description>${xmlEscape(FEED_DESC)}</description>`,
    '    <language>en</language>',
    `    <lastBuildDate>${new Date().toUTCString()}</lastBuildDate>`,
    ...(items ? [items] : []),
    '  </channel>',
    '</rss>',
    ''
  ].join('\n');
}

/* ------------------------------------------------------------------- main -- */
async function main() {
  const posts = await collectPosts();
  const index = { generated: new Date().toISOString(), posts };
  const json = JSON.stringify(index, null, 2) + '\n';

  await writeFile(path.join(BLOG_DIR, 'posts.json'), json, 'utf8');
  await writeFile(path.join(DATA_DIR, 'blog.json'), json, 'utf8');
  await writeFile(path.join(ROOT, 'feed.xml'), buildFeed(posts), 'utf8');

  for (const message of warnings) console.warn(`warning: ${message}`);
  console.log(
    `blog index rebuilt: ${posts.length} post(s) -> blog/posts.json, data/blog.json, feed.xml`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
