/* ==========================================================================
   Site configuration.

   Single source of truth for the repositories this site reads, the cache and
   snapshot policy, and the small amount of editorial content the GitHub API
   cannot supply (card summaries, the archival changelog entry, the official
   platform list). Editorial values are written as `{ en, bn }` so both
   languages read from one place — pick one with AVRO_I18N.pick(value).
   ========================================================================== */
window.AVRO = {
  /* Canonical URL of this site — used for canonical/og tags and the sitemap. */
  site: 'https://raselrahmanrocky.github.io/Avro-Keyboard/',
  siteName: 'Avro Keyboard Community Edition',

  /* English is the default. Bangla is a one-click switch and a ?lang=bn link. */
  lang: 'en',
  langs: ['en', 'bn'],

  /* The one repository this site reads from. */
  source: {
    owner: 'raselrahmanrocky',
    repo: 'Avro-Keyboard',
    branch: 'main',
    /* Branch holding the untouched upstream baseline, used for the
       "commits ahead of official" figure. */
    baseline: 'official'
  },

  /* The archived official upstream, shown as the comparison baseline. */
  official: {
    owner: 'mugli',
    repo: 'Avro-Keyboard',
    version: '5.6.0',
    released: '2019-08-27',
    site: 'https://www.omicronlab.com/',
    installerUrl: 'https://www.omicronlab.com/avro-keyboard-download.html',
    portableUrl: 'https://www.omicronlab.com/avro-keyboard-portable-download.html',
    platform: {
      en: 'Windows 10, 8.1, 8, XP — 32-bit and 64-bit',
      bn: 'Windows 10, 8.1, 8, XP — ৩২-bit ও ৬৪-bit'
    },
    licence: {
      en: 'MPL-1.1 (source)',
      bn: 'MPL-1.1 (সোর্স)'
    }
  },

  cacheKey: 'avro-gh-v1',
  langKey: 'avro-lang',
  themeKey: 'avro-theme',

  /* Anonymous GitHub API calls are capped at 60/hour per visitor IP, so every
     response is cached for this long. On failure the saved snapshot is used
     first and the committed snapshot in data/ last. */
  ttl: 10 * 60 * 1000,

  /* How many releases the download grid considers. */
  maxReleases: 3,
  /* Cards the grid should settle on when fewer releases exist. */
  minCards: 3,

  /* Release tags pinned so the page structure never depends on a fetch. */
  fallbackTags: ['v6.0.2-beta'],

  /* Card summaries. Releases without an entry get one derived from the first
     meaningful paragraph of their own release notes. */
  summaries: {
    'v6.0.2-beta': {
      en:
        'Native 64- and 32-bit builds, a new file-based ANSI/Bijoy engine, the Text ' +
        'Converter built into the app, a resource browser with SHA-256 verification ' +
        'and a startup log — the first public beta of the Community Edition.',
      bn:
        '৬৪ ও ৩২-বিট নেটিভ বিল্ড, ফাইল-ভিত্তিক নতুন ANSI/Bijoy ইঞ্জিন, অ্যাপের ভেতরে Text Converter, ' +
        'SHA-256 যাচাইসহ রিসোর্স ব্রাউজার, স্টার্টআপ লগ — Community Edition-এর প্রথম পাবলিক বেটা।'
    }
  },

  /* Editorial copy for the changelog's archival entry describing the last
     official release. Facts verified against omicronlab.com and the archived
     upstream repository's metadata. */
  officialArchive: {
    tag: 'official-5.6.0',
    note: {
      en:
        'This is the last release of the official Avro Keyboard. It is OmicronLab\'s ' +
        'work, not ours — it is listed here only as a point of reference, because no ' +
        'further official version has appeared since.',
      bn:
        'এটি Official Avro Keyboard-এর শেষ রিলিজ। OmicronLab-এর এটি আমাদের ' +
        'রিলিজ নয় — শুধু ইতিহাসের রেফারেন্স হিসেবে এখানে রাখা হয়েছে, কারণ এরপর ' +
        'আর কোনো নতুন অফিসিয়াল ভার্সন আসেনি।'
    }
  }
};
