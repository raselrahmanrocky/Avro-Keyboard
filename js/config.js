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

  /* Hero headline cycle: one sentence per entry, split at its first comma —
     the head renders in plain text, the tail in the gradient span. Both
     languages sit side by side so a locale switch reads the same list. The
     two user-supplied lists merged, near-duplicates dropped. */
  heroCycle: [
    { en: 'Type Bangla,type it reliably.', bn: 'বাংলা লিখুন,আরও নির্ভরযোগ্য।' },
    { en: 'Open code, lightened load.', bn: 'উন্মুক্ত কোড, হালকা লোড।' },
    { en: 'Community built, zero guilt.', bn: 'কমিউনিটির সম্বল, নিশ্চিন্ত টাইপিংয়ের শক্তি।' },
    { en: 'Your trustworthy key, forever free.', bn: 'বিশ্বস্ত টাইপিং, নিখুঁত ফিলিং।' },
    { en: 'Fixed for today, write your way.', bn: 'নতুন যুগের সমাধান, নিখুঁত লেখার অভিযান।' },
    { en: 'No crashes ahead, smooth typing instead.', bn: 'ঝামেলামুক্ত লিখন, স্বাচ্ছন্দ্যময় প্রতি ক্ষণ।' },
    { en: 'Modern code, seamless mode.', bn: 'আধুনিক সমাধান, সাবলীল বাংলা গান।' },
    { en: 'Fix the bugs, catch the rhythm.', bn: 'সমস্যাগুলো দূর করো, টাইপিংয়ের সুর ধরো।' },
    { en: 'Safe and sound, true power found.', bn: 'সম্পূর্ণ নিরাপদ, কাটবে সব বিপদ।' },
    { en: 'Keep data inside, with no tracking in sight.', bn: 'তথ্য থাকবে গোপনেই, লিখতে কোনো ট্র্যাকিং নেই।' },
    { en: 'Pure and clean, the finest typing scene.', bn: 'নিরাপদ কিবোর্ড, কাজের গতি অনবোর্ড।' },
    { en: 'Privacy first, typing at its best.', bn: 'গোপনীয়তা সুরক্ষিত, টাইপিং অভিজ্ঞতা দূরন্ত।' },
    { en: 'Type with speed, all you need.', bn: 'দ্রুত টাইপিং গতি, কাজের দারুণ উন্নতি।' },
    { en: 'Words that flow, watch your ideas grow.', bn: 'শব্দ ফুটুক অবলীলায়, নতুন চিন্তার সীমানায়।' },
    { en: 'Simply type, forget the hype.', bn: 'সহজ বাংলা রূপায়ন, দ্রুত টাইপ অনুক্ষণ।' },
    { en: 'Type with ease, stay at peace.', bn: 'সহজে লিখুন, নিশ্চিন্ত থাকুন।' },
    { en: 'Type Bangla free, stay worry-free.', bn: 'বাংলা লিখুন, নির্ভয়ে থাকুন।' },
    { en: 'Write with trust, speed is a must.', bn: 'লিখুন নির্ভয়ে, নতুন প্রত্যয়ে।' },
    { en: 'Type with grace, set your pace.', bn: 'বাংলা লিখুন সহজে, ভাষা ছড়াক মনের রসে।' },
    { en: 'Express your mind, leave worries behind.', bn: 'মনের ভাব প্রকাশে, বাংলা থাকুক পাশে।' },
    { en: 'Type so fast, built to last.', bn: 'গতিময় লিখন, দীর্ঘস্থায়ী বাঁধন।' },
    { en: 'Words flow free, as fast as can be.', bn: 'শব্দ ফুটুক স্বাচ্ছন্দ্যে, ভাষা মাতুক আনন্দে।' },
    { en: 'Free and open, trust unbroken.', bn: 'মুক্ত ব্যবহারে, আস্থা থাকবে বারে বারে।' },
    { en: 'Open to create, simple and great.', bn: 'সবার জন্য উন্মুক্ত, অভিজ্ঞতায় নতুনত্ব।' },
    { en: 'Code is free, for you and me.', bn: 'সবার মাঝে বাংলা, খুলবে নতুন জানালা।' },
    { en: 'New era, smooth keyboard aura.', bn: 'নতুন যুগের লিখন, সাবলীল প্রতি ক্ষণ।' },
    { en: 'Type smoothly, live smartly.', bn: 'লিখুন স্মার্টলি, কাজ করুন স্মুথলি।' },
    { en: 'Clear and bright, typing done right.', bn: 'সহজ টাইপিং, দারুণ ফিলিং।' },
    { en: 'Pure Bangla, zero worry.', bn: 'খাঁটি বাংলা, নেই কোনো ঝামেলা।' },
    { en: 'Built by all, pure and free.', bn: 'সবার জন্য বাংলা, মুক্ত এবং নিষ্কন্টক।' }

  ],

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
