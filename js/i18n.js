/* ==========================================================================
   Internationalisation.

   English is the default and the canonical language: the shipped HTML is
   written in English, which is what a visitor without JavaScript, a search
   engine crawler or a social-media scraper sees. This module captures that
   English from the DOM once, then swaps it for the dictionary text when the
   visitor picks Bangla — so the English copy lives in exactly one place and
   switching back can never drift.

   The `bn` dictionary therefore only carries the page prose, while strings the
   JavaScript layer itself renders (status lines, card labels, markdown
   headings) are carried for both languages under `dict.en` / `dict.bn`.

   Numbers stay in Latin digits in both languages, matching how this project
   already writes version tags, file sizes and SHA-256 digests. Dates and
   relative times are localised.
   ========================================================================== */
window.AVRO_I18N = (function () {
  'use strict';

  var cfg = window.AVRO || {};
  var STORE_KEY = 'avro-lang';
  var DEFAULT = 'en';
  var SUPPORTED = ['en', 'bn'];
  var LABELS = { en: { native: 'English', code: 'EN' }, bn: { native: 'বাংলা', code: 'বাং' } };

  /* Locale tags for Intl. `-u-nu-latn` keeps Latin digits with localised
     month and unit names instead of mixing Bengali numerals into sentences
     that also contain Latin version numbers and hashes. */
  var INTL_DATE = { en: 'en-GB', bn: 'bn-BD-u-nu-latn' };
  var INTL_REL = { en: 'en', bn: 'bn-u-nu-latn' };

  /* Attributes that can be localised. `data-i18n-content="key"` covers
     <meta name="description">, `data-i18n-alt` the splash screen, and so on. */
  var ATTRS = ['aria-label', 'title', 'alt', 'content', 'placeholder'];

  var dict = {
    /* ------------------------------------------------------------ English --
       Only strings that the JavaScript layer renders. Page prose in English
       is already in the HTML and is captured from there. */
    en: {
      'lang.label': 'Language',
      'lang.en': 'EN',
      'lang.bn': 'বাং',
      'lang.enFull': 'English',
      'lang.bnFull': 'বাংলা',

      'theme.toDark': 'Switch to dark theme',
      'theme.toLight': 'Switch to light theme',

      'status.loading': 'Fetching live data…',
      'status.live': 'Live data from the GitHub API',
      'status.partial': 'Some values are live, the rest came from the saved snapshot',
      'status.saved': 'Saved snapshot from {when} — the GitHub API is not responding',
      'status.bundled': 'Bundled snapshot from {when} — the GitHub API is not responding',
      'status.error': 'No data available right now (no saved snapshot either)',
      'data.whenUnknown': 'at an unknown time',

      'releases.status.loading': 'Fetching releases…',
      'releases.status.live': 'Live from the GitHub releases API · {n} releases found',
      'releases.status.live.one': 'Live from the GitHub releases API · {n} release found',
      'releases.status.saved': 'From the snapshot saved on your last visit ({when}) · {n} of them are our builds',
      'releases.status.saved.one': 'From the snapshot saved on your last visit ({when}) · {n} of them is our build',
      'releases.status.bundled': 'From the bundled snapshot ({when}) · {n} of them are our builds',
      'releases.status.bundled.one': 'From the bundled snapshot ({when}) · {n} of them is our build',
      'releases.status.error': 'The GitHub releases API did not respond and there is no snapshot.',
      'releases.empty.filtered': 'No build matches this filter yet.',
      'releases.empty.none': 'No releases found.',
      'releases.ribbon.prerelease': 'Pre-release (beta)',
      'releases.ribbon.stable': 'Latest stable',
      'releases.ribbon.portable': 'Portable edition',
      'releases.ribbon.officialPortable': 'Official portable',
      'releases.ribbon.official': 'Official 5.6.0',
      'releases.when': 'Released {date}',
      'releases.spec.size': 'File size',
      'releases.spec.downloads': 'Downloads',
      'releases.spec.arch': 'Architecture',
      'releases.spec.licence': 'Licence',
      'releases.spec.version': 'Version',
      'releases.spec.released': 'Released',
      'releases.spec.platform': 'Platform',
      'releases.spec.sourceLicence': 'Source licence',
      'releases.spec.status': 'Status',
      'releases.downloadExe': 'Download .exe ({arch})',
      'releases.downloadZip': 'Download .zip ({arch})',
      'releases.noFile': 'File not available',
      'releases.portable': 'Portable',
      'releases.details': '{title} — changelog and details',
      'releases.official.cta': 'From OmicronLab',
      'releases.official.summary':
        'The last official stable release. No update has appeared since 2019 — this is the baseline the comparison is measured against.',
      'releases.officialPortable.summary':
        'The official portable edition — the older package that runs without installing anything. The comparison baseline.',

      'changelog.status.loading': 'Fetching the changelog…',
      'changelog.status.live': 'Live from the GitHub API · {n} releases',
      'changelog.status.live.one': 'Live from the GitHub API · {n} release',
      'changelog.status.saved': 'From the snapshot saved on your last visit ({when}) — the GitHub API is not responding',
      'changelog.status.bundled': 'From the bundled snapshot ({when}) — the GitHub API is not responding',
      'changelog.status.error': 'The changelog could not be loaded.',
      'changelog.empty': 'No releases found. The GitHub releases API did not respond and no snapshot could be loaded.',
      'changelog.mark.prerelease': 'Pre-release',
      'changelog.mark.stable': 'Stable',
      'changelog.mark.auto': 'Built from commits',
      'changelog.mark.autoShort': 'Automatic',
      'changelog.mark.archived': 'Archived',
      'changelog.mark.official': 'Official',
      'changelog.when': 'Released: {date}',
      'changelog.viewOnGithub': 'View the release on GitHub',
      'changelog.assets.summary': 'Files and SHA-256 ({n})',
      'changelog.assets.summary.one': 'File and SHA-256 ({n})',
      'changelog.assets.downloads': '{n} downloads',
      'changelog.assets.downloads.one': '{n} download',
      'changelog.autonotes.lead': 'No release notes were written for this release. The list below was generated automatically from the commits it contains.',
      'changelog.autonotes.unavailable': 'The commit list for this release could not be fetched from the GitHub API.',
      'changelog.autonotes.truncated': 'Showing the most recent 100 commits.',
      'changelog.history.title': 'Development history — {tag}',
      'changelog.history.when': '{n} commits up to this tag',
      'changelog.history.when.one': '{n} commit up to this tag',
      'changelog.history.nav': 'Development history',
      'changelog.nav.commits': '{n} commits',
      'changelog.nav.commits.one': '{n} commit',
      'changelog.nav.heading': 'Versions',
      'changelog.nav.official': 'Official {version}',
      'changelog.official.when': 'Last official release: {date}',
      'changelog.official.status': 'Archived / read-only',
      'changelog.official.download': 'Official download at OmicronLab.com',
      'changelog.official.source': 'Archived source',
      'changelog.unknownMonth': 'Unknown',
      'audit.archived': 'Read-only (archived)',
      'audit.active': 'Active',
      'audit.freshness': 'Last updated {when}'
    },

    /* ------------------------------------------------------------- Bangla --
       Page prose plus the JavaScript-rendered strings above. Every key that
       appears as `data-i18n` in the HTML must have an entry here. */
    bn: {
      'lang.label': 'ভাষা',
      'lang.en': 'EN',
      'lang.bn': 'বাং',
      'lang.enFull': 'English',
      'lang.bnFull': 'বাংলা',

      'theme.toDark': 'ডার্ক থিমে যান',
      'theme.toLight': 'লাইট থিমে যান',

      'status.loading': 'লাইভ ডেটা আনা হচ্ছে…',
      'status.live': 'GitHub API থেকে লাইভ ডেটা',
      'status.partial': 'কিছু মান লাইভ, বাকিটা সংরক্ষিত স্ন্যাপশট থেকে',
      'status.saved': 'আপনার গত ভিজিটে সংরক্ষিত স্ন্যাপশট ({when}) — GitHub API এখন সাড়া দিচ্ছে না',
      'status.bundled': 'সাইটের সঙ্গে দেওয়া স্ন্যাপশট ({when}) — GitHub API এখন সাড়া দিচ্ছে না',
      'status.error': 'ডেটা এখন পাওয়া যাচ্ছে না (সংরক্ষিত স্ন্যাপশটও নেই)',
      'data.whenUnknown': 'অজানা সময়ে',

      'releases.status.loading': 'রিলিজ তালিকা আনা হচ্ছে…',
      'releases.status.live': 'GitHub releases API থেকে লাইভ · {n}টি রিলিজ পাওয়া গেছে',
      'releases.status.live.one': 'GitHub releases API থেকে লাইভ · {n}টি রিলিজ পাওয়া গেছে',
      'releases.status.saved': 'আপনার গত ভিজিটে সংরক্ষিত স্ন্যাপশট ({when}) — এর মধ্যে {n}টি আমাদের বিল্ড',
      'releases.status.saved.one': 'আপনার গত ভিজিটে সংরক্ষিত স্ন্যাপশট ({when}) — এর মধ্যে {n}টি আমাদের বিল্ড',
      'releases.status.bundled': 'সাইটের সঙ্গে দেওয়া স্ন্যাপশট ({when}) — এর মধ্যে {n}টি আমাদের বিল্ড',
      'releases.status.bundled.one': 'সাইটের সঙ্গে দেওয়া স্ন্যাপশট ({when}) — এর মধ্যে {n}টি আমাদের বিল্ড',
      'releases.status.error': 'GitHub releases API সাড়া দেয়নি এবং স্ন্যাপশটও নেই।',
      'releases.empty.filtered': 'এই ফিল্টারে এখন কোনো বিল্ড নেই।',
      'releases.empty.none': 'কোনো রিলিজ পাওয়া যায়নি।',
      'releases.ribbon.prerelease': 'ইন্সটলার এডিশন',
      'releases.ribbon.stable': 'সর্বশেষ স্থিতিশীল',
      'releases.ribbon.portable': 'পোর্টেবল এডিশন',
      'releases.ribbon.officialPortable': 'অফিসিয়াল পোর্টেবল',
      'releases.ribbon.official': 'অফিসিয়াল 5.6.0',
      'releases.when': 'রিলিজ: {date}',
      'releases.spec.size': 'ফাইল সাইজ',
      'releases.spec.downloads': 'ডাউনলোড',
      'releases.spec.arch': 'আর্কিটেকচার',
      'releases.spec.licence': 'লাইসেন্স',
      'releases.spec.version': 'ভার্সন',
      'releases.spec.released': 'রিলিজ',
      'releases.spec.platform': 'প্ল্যাটফর্ম',
      'releases.spec.sourceLicence': 'সোর্স লাইসেন্স',
      'releases.spec.status': 'অবস্থা',
      'releases.downloadExe': '.exe নামান ({arch})',
      'releases.downloadZip': '.zip নামান ({arch})',
      'releases.noFile': 'ফাইল পাওয়া যায়নি',
      'releases.portable': 'পোর্টেবল',
      'releases.details': '{title} — চেঞ্জলগ ও বিস্তারিত',
      'releases.official.cta': 'OmicronLab থেকে নিন',
      'releases.official.summary':
        'অফিসিয়াল সর্বশেষ স্থিতিশীল রিলিজ। ২০১৯ সালের পর আর কোনো আপডেট আসেনি — এটিই সেই বেসলাইন যার সঙ্গে তুলনা করা হয়েছে।',
      'releases.officialPortable.summary':
        'অফিসিয়াল পোর্টেবল এডিশন — ইনস্টল ছাড়াই চালানোর পুরোনো প্যাকেজ। তুলনার বেসলাইন।',

      'changelog.status.loading': 'চেঞ্জলগ আনা হচ্ছে…',
      'changelog.status.live': 'GitHub API থেকে লাইভ · {n}টি রিলিজ',
      'changelog.status.live.one': 'GitHub API থেকে লাইভ · {n}টি রিলিজ',
      'changelog.status.saved': 'আপনার গত ভিজিটে সংরক্ষিত স্ন্যাপশট ({when}) — GitHub API এখন সাড়া দিচ্ছে না',
      'changelog.status.bundled': 'সাইটের সঙ্গে দেওয়া স্ন্যাপশট ({when}) — GitHub API এখন সাড়া দিচ্ছে না',
      'changelog.status.error': 'চেঞ্জলগ লোড করা যায়নি।',
      'changelog.empty': 'কোনো রিলিজ পাওয়া যায়নি। GitHub releases API সাড়া দেয়নি এবং স্ন্যাপশটও লোড হয়নি।',
      'changelog.mark.prerelease': 'Pre-release',
      'changelog.mark.stable': 'স্থিতিশীল',
      'changelog.mark.auto': 'Commit থেকে তৈরি',
      'changelog.mark.autoShort': 'স্বয়ংক্রিয়',
      'changelog.mark.archived': 'আর্কাইভকৃত',
      'changelog.mark.official': 'অফিসিয়াল',
      'changelog.when': 'রিলিজ: {date}',
      'changelog.viewOnGithub': 'GitHub-এ রিলিজ দেখুন',
      'changelog.assets.summary': 'ফাইল ও SHA-256 ({n})',
      'changelog.assets.summary.one': 'ফাইল ও SHA-256 ({n})',
      'changelog.assets.downloads': '{n}টি ডাউনলোড',
      'changelog.assets.downloads.one': '{n}টি ডাউনলোড',
      'changelog.autonotes.lead': 'এই রিলিজে কোনো release note লেখা হয়নি। রিলিজের কমিটগুলো থেকে নিচের তালিকা স্বয়ংক্রিয়ভাবে তৈরি করা হয়েছে।',
      'changelog.autonotes.unavailable': 'এই রিলিজের কমিট তালিকা GitHub API থেকে আনা যায়নি।',
      'changelog.autonotes.truncated': 'সর্বশেষ 100টি commit দেখানো হচ্ছে।',
      'changelog.history.title': 'উন্নয়নের ইতিহাস — {tag}',
      'changelog.history.when': 'এই ট্যাগ পর্যন্ত {n}টি commit',
      'changelog.history.when.one': 'এই ট্যাগ পর্যন্ত {n}টি commit',
      'changelog.history.nav': 'উন্নয়নের ইতিহাস',
      'changelog.nav.commits': '{n}টি commit',
      'changelog.nav.commits.one': '{n}টি commit',
      'changelog.nav.heading': 'সংস্করণ',
      'changelog.nav.official': 'অফিসিয়াল {version}',
      'changelog.official.when': 'অফিসিয়াল সর্বশেষ রিলিজ: {date}',
      'changelog.official.status': 'Archived / read-only',
      'changelog.official.download': 'OmicronLab.com-এ অফিসিয়াল ডাউনলোড',
      'changelog.official.source': 'আর্কাইভ করা সোর্স',
      'changelog.unknownMonth': 'অজানা',

      /* ---- shared chrome ---- */
      'nav.skip': 'মূল কনটেন্টে যান',
      'nav.toTop': 'উপরে ফিরুন',
      'nav.main': 'প্রধান নেভিগেশন',
      'nav.footer': 'ফুটার লিংক',
      'nav.variants': 'সংস্করণ তালিকা',
      'nav.toc': 'সূচিপত্র',
      'nav.home': 'হোম',
      'nav.improvements': 'উন্নয়ন',
      'nav.features': 'ফিচার',
      'nav.install': 'ইনস্টল',
      'nav.download': 'ডাউনলোড',
      'nav.changelog': 'চেঞ্জলগ',
      'nav.privacy': 'প্রাইভেসি',
      'brand.name': 'অভ্র কিবোর্ড<span class="ce-tag">Community Edition</span>',
      'brand.tagline': 'ওপেন সোর্স · MPL-2.0',
      'actions.download': 'ডাউনলোড',
      'footer.reportBug': 'বাগ রিপোর্ট <i class="fa-solid fa-arrow-up-right-from-square" aria-hidden="true"></i>',
      'footer.ahead': 'অফিসিয়াল বেসলাইনের উপরে <span data-ahead-note>—</span> commit · MPL-2.0',
      'footer.legal': 'Avro Keyboard Community Edition — Avro Keyboard-এর ওপেন সোর্স কোডের (MPL-2.0) একটি স্বতন্ত্র কন্টিনিউয়েশন। <strong>OmicronLab বা এর মূল ডেভেলপারদের সঙ্গে সম্পৃক্ত নয়</strong>। Avro Keyboard-এর মূল সোর্স ও কপিরাইট OmicronLab (Mehdi Hasan Khan)-এর।',
      'footer.licenceNote': 'MPL-2.0 · OmicronLab-এর সঙ্গে সম্পৃক্ত নয়',

      /* ---- index.html ---- */
      'meta.title': 'Avro Keyboard Community Edition — বাংলা টাইপিং, আরও নির্ভরযোগ্য',
      'meta.desc': 'Avro Keyboard Community Edition — অফিসিয়াল Avro Keyboard-এর ওপেন সোর্স কোড (MPL-2.0) থেকে স্বতন্ত্রভাবে রক্ষণাবেক্ষণ করা কন্টিনিউয়েশন। নেটিভ ৬৪/৩২-বিট বিল্ড, নতুন ANSI/Bijoy ইঞ্জিন, ইন-অ্যাপ কনভার্টার ও অটো আপডেট।',
      'hero.eyebrow': 'ওপেন সোর্স বাংলা IME · Community Edition',
      'hero.h1': 'বাংলা লিখুন,<br><span class="gradient">আরও নির্ভরযোগ্য।</span>',
      'hero.lead': 'আধুনিক উইন্ডোজের জন্য নতুন শক্তিতে ফিরে এসেছে <strong>অভ্র কিবোর্ড কমিউনিটি সংস্করণ!</strong> নতুন ৬৪-বিট আর্কিটেকচারে তৈরি এই সংস্করণে রয়েছে নিরবচ্ছিন্ন টাইপিং অভিজ্ঞতা, দ্রুতগতির Async Persistence এবং গ্রাফিম-ভিত্তিক ব্যাকস্পেস। এতে যুক্ত করা হয়েছে পাওয়ারফুল Qt-ভিত্তিক টেক্সট কনভার্টার এবং নীরব ত্রুটি রিকভারি সিস্টেম। আপনার তথ্যের সম্পূর্ণ নিরাপত্তা নিশ্চিত করতে এটি সম্পূর্ণ ওপেন-সোর্স ও ট্র্যাকিং-মুক্ত।',
      'hero.ctaDownload': '<i class="fa-solid fa-download" aria-hidden="true"></i> সর্বশেষ বিল্ড ডাউনলোড করুন',
      'hero.ctaSource': '<i class="fa-brands fa-github" aria-hidden="true"></i> সোর্স কোড দেখুন <i class="fa-solid fa-arrow-up-right-from-square" aria-hidden="true"></i>',
      'hero.tech1': 'Delphi 12 / C++',
      'hero.tech2': 'Qt 6 Core',
      'hero.tech3': 'x64 / x86 Native',
      'hero.tech4': 'Atomic File I/O',
      'hero.alt': 'অভ্র কিবোর্ডের স্প্ল্যাশ স্ক্রিন — বেগুনি পটভূমিতে অভ্র লোগো',
      'hero.floatTag': '<svg class="spark" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path fill="currentColor" d="M12 1.8c.6 5.6 4.6 9.6 10.2 10.2-5.6.6-9.6 4.6-10.2 10.2-.6-5.6-4.6-9.6-10.2-10.2 5.6-.6 9.6-4.6 10.2-10.2z"/></svg> <b>ভাষা হোক উন্মুক্ত</b><br>Community Edition',
      'stats.group': 'প্রজেক্টের লাইভ পরিসংখ্যান',
      'stat.commits': 'মোট git commit',
      'stat.stars': 'GitHub স্টার',
      'stat.forks': 'ফর্ক',
      'stat.contributors': 'অবদানকারী (পুরো ইতিহাস)',
      'stat.ahead': 'অফিসিয়াল বেসলাইনের চেয়ে এগিয়ে',
      'stat.pushed': 'সর্বশেষ পুশ',
      'improvements.kicker': 'সবচেয়ে গুরুত্বপূর্ণ পার্থক্য',
      'improvements.h2': 'অফিসিয়াল Avro Keyboard, <span class="gradient">এবং আমরা যা বদলেছি।</span>',
      'improvements.lead': 'অফিসিয়াল সর্বশেষ রিলিজ — <strong>5.6.0, 27 আগস্ট 2019</strong>। এরপর ক্যানোনিকাল সোর্স রিপোটি read-only করে দেওয়া হয়েছে। নিচের তুলনাটি সেই বেসলাইন এবং এই Community Edition-এর বর্তমান অবস্থার মধ্যে।',
      'audit.official.title': 'অফিসিয়াল Avro Keyboard',
      'audit.official.sub': 'OmicronLab · বেসলাইন বিল্ড',
      'audit.official.stars': 'GitHub স্টার',
      'audit.official.forks': 'ফর্ক',
      'audit.official.stamp': 'Archived',
      'audit.ce.title': 'Avro Keyboard Community Edition',
      'audit.ce.sub': 'এই রিপো · চলমান রক্ষণাবেক্ষণ',
      'audit.ce.commits': 'মোট commit',
      'audit.ce.ahead': 'বেসলাইনের চেয়ে এগিয়ে',
      'audit.ce.stamp': 'Active',
      /* The property rows share one sentence per label, so both cards always
         spell the comparison the same way. */
      'audit.row.stars': 'স্টার',
      'audit.row.forks': 'ফর্ক',
      'audit.row.contributors': 'অবদানকারী',
      'audit.row.language': 'ভাষা',
      'audit.row.latest': 'সর্বশেষ ট্যাগ',
      'audit.row.released': 'রিলিজের তারিখ',
      'audit.row.updated': 'শেষ আপডেট',
      'audit.row.license': 'লাইসেন্স',
      'audit.ce.desc': 'অফিসিয়াল বেসলাইনের অনেকটাই এগিয়ে — প্রতিটি commit একটি বাস্তব, রিপোর্ট করা সমস্যার সমাধান।',
      'audit.ce.cta': 'রিপোজিটরি',
      'audit.official.desc': '২০১৯ সাল থেকে 5.6.0-এ স্থির — যে প্রকাশিত বেসলাইনের সঙ্গে এই কন্টিনিউয়েশন তুলনা করা হয়।',
      'audit.official.cta': 'রিপোজিটরি',
      'ahead.note': 'ক্যানোনিকাল অফিসিয়াল সোর্সের বেসলাইনের উপরে ইতিমধ্যেই <span data-ahead-note>—</span>টি commit। অর্থাৎ কোডবেসটি নতুন করে লেখা নয় — পুরো ইতিহাস ধরে রাখা কন্টিনিউয়েশন।',
      'compare.caption': 'অফিসিয়াল Avro Keyboard 5.6.0 এবং Community Edition-এর তুলনা',
      'compare.th.topic': 'বিষয়',
      'compare.th.official': 'অফিসিয়াল 5.6.0',
      'compare.th.ce': 'Community Edition',
      'compare.sources': 'অফিসিয়াল কলামের তথ্যগুলো আসে OmicronLab.com-এর প্রকাশিত রিলিজ তথ্য এবং আর্কাইভ করা আপস্ট্রিম রিপোর মেটাডেটা থেকে। Community Edition কলামের প্রতিটি দাবির উৎস এই রিপোর Readme এবং 6.0.2-beta-এর release notes।',

      'cmp.g1': 'রক্ষণাবেক্ষণ ও ডিস্ট্রিবিউশন',
      'cmp.g1.r1.t': 'সক্রিয় আপডেট', 'cmp.g1.r1.o': 'সর্বশেষ রিলিজ 27 আগস্ট 2019; সোর্স রিপো archived', 'cmp.g1.r1.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>চলমান রক্ষণাবেক্ষণ, ট্যাগ করা রিলিজ',
      'cmp.g1.r2.t': 'ইনস্টলার', 'cmp.g1.r2.o': 'একটি 32-bit ইনস্টলার', 'cmp.g1.r2.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>ইনস্টলার ও পোর্টেবল — 64 ও 32-bit, মোট 4টি ফাইল',
      'cmp.g1.r3.t': 'কোড সাইনিং', 'cmp.g1.r3.o': '5.6.0 সাইন করা ছিল', 'cmp.g1.r3.c': '<span class="no"><i class="fa-solid fa-xmark" aria-hidden="true"></i></span>এখনো সাইন করা নয় — SHA-256 যাচাই করুন',

      'cmp.g2': 'ইঞ্জিন ও কনভার্সন',
      'cmp.g2.r1.t': 'ANSI / Bijoy ম্যাপিং', 'cmp.g2.r1.o': 'একটি হার্ডকোডেড ম্যাপিং', 'cmp.g2.r1.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>V1–V5 প্রতিটি এনকোডিং ফাইল-ভিত্তিক',
      'cmp.g2.r2.t': 'প্রথম ব্যবহার', 'cmp.g2.r2.o': 'ঠান্ডা ইঞ্জিন — প্রথম ব্যবহারে জ্যাম', 'cmp.g2.r2.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>ইঞ্জিন আগে থেকেই গরম, ভার্সন সুইচ শূন্য-অ্যালোকেশনে',
      'cmp.g2.r3.t': 'ব্যাকস্পেস', 'cmp.g2.r3.o': 'যৌগিক অক্ষর ভেঙে একক মাত্রা ফেলে যায়', 'cmp.g2.r3.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>পুরো অক্ষর-গ্রুপ (grapheme) মুছে',
      'cmp.g2.r4.t': 'যুক্তবর্ণ', 'cmp.g2.r4.o': 'কিছু ভুল গ্লিফ', 'cmp.g2.r4.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>ম্যাপিং টেবিল হালনাগাদ',
      'cmp.g2.r5.t': 'ক্যাশ রিস্টার্ট', 'cmp.g2.r5.o': '—', 'cmp.g2.r5.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>এনকোডিং সেটিং ক্যাশ রিস্টার্টের পরও টিকে থাকে',

      'cmp.g3': 'ইন্টারফেস',
      'cmp.g3.r1.t': 'থিম', 'cmp.g3.r1.o': 'সীমিত', 'cmp.g3.r1.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>অ্যাপ-ওয়াইড থিম ও প্যালেট সিস্টেম',
      'cmp.g3.r2.t': 'এনকোডিং নির্বাচন', 'cmp.g3.r2.o': 'আলাদা পিকার', 'cmp.g3.r2.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>ট্রেতে “Select ANSI Encoding”, সব পিকারের সঙ্গে সিঙ্ক',
      'cmp.g3.r3.t': 'তালিকা সাজানো', 'cmp.g3.r3.o': 'সাধারণ সাজানো', 'cmp.g3.r3.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>V1 → V5 নেচারাল সোর্ট',
      'cmp.g3.r4.t': 'আইকন', 'cmp.g3.r4.o': 'সাধারণ', 'cmp.g3.r4.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>লেআউট-ভিত্তিক আইকন',
      'cmp.g3.r5.t': 'গ্লোবাল হটকি', 'cmp.g3.r5.o': 'সীমিত', 'cmp.g3.r5.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>অ্যাপটিতে আপনার নিজের পছন্দমতো হটকি সেট করুন; সেভ করার আগেই কী-কনফ্লিক্ট ধরে',

      'cmp.g4': 'নির্ভরযোগ্যতা',
      'cmp.g4.r1.t': 'স্টার্টআপ ব্যর্থতা', 'cmp.g4.r1.o': 'খারাপ সেটিংস, লক করা রেজিস্ট্রি, হারানো ফন্ট বা নষ্ট Database.db3 হলে চুপচাপ বন্ধ', 'cmp.g4.r1.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>প্রতিটি ধাপ সুরক্ষিত, দৃশ্যমান রিপোর্ট',
      'cmp.g4.r2.t': 'ডায়াগনস্টিক লগ', 'cmp.g4.r2.o': 'ছিল না', 'cmp.g4.r2.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>AvroStartup.log — কখনো keystroke লেখে না',
      'cmp.g4.r3.t': 'নতুন লেআউট / স্কিন', 'cmp.g4.r3.o': 'চালু করতে অ্যাপ রিস্টার্ট লাগত', 'cmp.g4.r3.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>ফাইল ফেললেই মেনু অটো-রিফ্রেশ',
      'cmp.g4.r4.t': 'রিসোর্স ডাউনলোড', 'cmp.g4.r4.o': 'আলাদা সাইট থেকে হাতে', 'cmp.g4.r4.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>ইন-অ্যাপ ব্রাউজার, SHA-256 যাচাইয়ের পর ইনস্টল',
      'cmp.g4.r5.t': 'আপডেট', 'cmp.g4.r5.o': 'নিজে খুঁজে নামাতে হতো', 'cmp.g4.r5.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>ইন-অ্যাপ অটো আপডেট — সঠিক আর্কিটেকচার, বিটা চ্যানেল টগল',

      'cmp.g5': 'কনভার্টার, বিল্ড ও লাইসেন্স',
      'cmp.g5.r1.t': 'Text Converter', 'cmp.g5.r1.o': 'খুব বেশি শব্দ থাকলে এটি আটকে যায়।', 'cmp.g5.r1.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>অ্যাপটির মধ্যেই এটি যুক্ত রয়েছে এবং বড় টেক্সটের ক্ষেত্রে এটি আটকে যায় না।',
      'cmp.g5.r2.t': 'Qt কনভার্টার', 'cmp.g5.r2.o': 'ছিল না', 'cmp.g5.r2.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>Qt 6 C++ পোর্ট, <code>--mapping-dir</code> সুইচসহ',
      'cmp.g5.r3.t': 'বিল্ড ব্যবস্থা', 'cmp.g5.r3.o': 'Delphi 2010 + মালিকানাধীন DISQLite3, ICS, JVCL/JCL',      'cmp.g5.r3.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>Delphi 12 Community Edition, 3য়-পক্ষ নির্ভরতা ছাড়াই',
      'cmp.g5.r4.t': 'লাইসেন্স', 'cmp.g5.r4.o': 'MPL-1.1 (অফিসিয়াল সোর্স)', 'cmp.g5.r4.c': '<span class="yes"><i class="fa-solid fa-check" aria-hidden="true"></i></span>MPL-2.0 + Qt LGPLv3-এর শর্ত documented',

      'detail.1.title': 'নতুন ANSI/Bijoy কনভার্সন ইঞ্জিন',
      'detail.1.body': 'ভেতরের একমাত্র হার্ডকোডেড ম্যাপিং সরিয়ে V1–V5 প্রতিটি এনকোডিং ফাইল-ভিত্তিক করা হয়েছে। ইঞ্জিন আগে থেকেই গরম থাকে, ভার্সন সুইচ হয় শূন্য-অ্যালোকেশনে, আর ক্যাশ রিস্টার্টের পরেও সেটিং টিকে থাকে।',
      'detail.2.title': 'Avro Text Converter এখন অ্যাপের ভেতরেই',
      'detail.2.body': 'ট্রে মেনু থেকে বা <strong>Ctrl+Alt+T</strong> চেপে চালু করুন। Unicode ↔ ANSI দুই দিকেই কনভার্ট করে, আর বড় লেখা কনভার্ট করার সময় উইন্ডো ফ্রিজ হয় না — কাজটা ব্যাকগ্রাউন্ডে চলে।',
      'detail.3.title': 'ইন-অ্যাপ “Download Resources”',
      'detail.3.body': 'লেআউট, স্কিন ও ANSI ম্যাপিং প্যাক অ্যাপের ভেতর থেকেই খুঁজে নামান। প্রতিটি ফাইল <strong>SHA-256</strong> দিয়ে যাচাই হয়ে তবেই ইনস্টল হয়, আর রিস্টার্ট ছাড়াই লোড হয়ে যায়।',
      'detail.4.title': 'এই GitHub রিপো থেকেই অটো আপডেট',
      'detail.4.body': 'আপনার চালু আর্কিটেকচারের সঠিক ফাইল বেছে নেয়, ডাউনলোড লিংক লাইভ যাচাই করে তবেই অফার দেয়, পোর্টেবল বিল্ডে পোর্টেবল প্যাকেজ দেয়, আর বিটা চ্যানেলের টগল থাকে।',
      'detail.5.title': 'স্টার্টআপ কখনো নীরবে ব্যর্থ হয় না',
      'detail.5.body': 'খারাপ সেটিংস, লক করা রেজিস্ট্রি, হারানো ফন্ট বা নষ্ট <code>Database.db3</code> — এসব আগে কোনো উইন্ডো না দেখিয়েই অ্যাপ বন্ধ করে দিত। এখন প্রতিটি ধাপ সুরক্ষিত, সাথে দৃশ্যমান রিপোর্ট আর <code>AvroStartup.log</code>।',
      'detail.6.title': 'ইন্টারফেস ও থিম',
      'detail.6.body': 'অ্যাপ-ওয়াইড থিম ও প্যালেট সিস্টেম, ট্রেতে “Select ANSI Encoding” মেনু যা সব পিকারের সঙ্গে একসাথে সিঙ্ক, লেআউট-ভিত্তিক আইকন এবং V1 → V5-এর মতো সঠিক নেচারাল সোর্ট।',
      'detail.7.title': 'নেটিভ 64/32-bit ও সত্যিকারের পোর্টেবল',
      'detail.7.body': 'অফিসিয়ালে ছিল একটাই ৩২-বিট ইনস্টলার; এখানে ইনস্টলার ও পোর্টেবল — দুই আর্কিটেকচারেই। পোর্টেবলে সেটিংস <code>Settings.xml</code>-এ exe-এর পাশেই থাকে, USB থেকে চালিয়ে ফোল্ডার মুছে দিলেই মেশিন পরিষ্কার।',
      'detail.8.title': 'সম্প্রদায়ের অবদান',
      'detail.8.body': '3য়-পক্ষ নির্ভরতা ছাড়াই লেটেস্ট ফ্রি Delphi Community Edition-এ বিল্ড হয় (<code>build-ce.bat</code>)। অবদানের পথ খোলা — Kotlin নয়, Delphi ও Qt কনভার্টার দুটোতেই।',
      'detail.9.title': 'ট্র্যাকিং নেই, টেলিমেট্রি নেই',
      'detail.9.body': 'অ্যাপ কোনো টেলিমেট্রি পাঠায় না, আর <code>AvroStartup.log</code>-এ কখনো আপনার টাইপ করা লেখা থাকে না। ইনস্টল না করে পোর্টেবল ফোল্ডার ব্যবহার করলে সিস্টেম-ওয়াইড কিছুই রেজিস্টার হয় না।',

      'honest.title': 'যা এখনো সীমাবদ্ধতা — সোজাসুজি বলে রাখা ভালো',
      'honest.i1': '<strong>এটি একটি স্বতন্ত্র কন্টিনিউয়েশন।</strong> Avro Keyboard-এর ওপেন সোর্স কোড (MPL-2.0) থেকে আলাদা একটি কন্টিনিউয়েশন — OmicronLab-এর সঙ্গে সম্পৃক্ত নয়। অফিসিয়াল সাইট ও পুরোনো ভার্সন আগের মতোই OmicronLab.com-এ আছে।',
      'honest.i2': '<strong>বাইনঅ্যারিগুলো এখনো কোড-সাইন করা নয়</strong> (অফিসিয়াল 5.6.0 সাইন করা ছিল), তাই Windows SmartScreen “More info → Run anyway” দেখাতে পারে। ডাউনলোড করা ফাইলের SHA-256 মিলিয়ে নিলে নিশ্চিত থাকা যায়।',
      'honest.i3': '<strong>পোর্টেবল এডিশনও তিনটি HKCU কী লেখে</strong> — <code>LowLevelHooksTimeout</code> (যাতে Windows নীরবে কীবোর্ড হুক ফেলে না দেয়) এবং পোর্টেবল Siyam Rupali ফন্ট নিবন্ধিত থাকা অবস্থায় দুটি IE ফন্ট মান, যা ফন্ট সরালে আগের অবস্থায় ফিরে যায়। সিস্টেম-ওয়াইড কিছুই ইনস্টল হয় না।',
      'honest.i4': '<strong>কিছু রিসোর্স পাবলিক রিপোতে নেই।</strong> মালিকানাধীন ANSI এনকোডিং কনফিগারেশন, নির্দিষ্ট ম্যাপিং ফাইল ও কী মেটেরিয়াল আলাদা রাখা হয়েছে। ফলে এই রিপো ক্লোন করে বিল্ড করলে অ্যাপ ডিফল্ট-কী <code>.AvroEnco</code> কন্টেইনার খুলতে পারে না — তখন বিভ্রান্তিকর ডিকোড এররের বদলে স্পষ্টভাবে “secret unavailable” জানায়। এটাই ক্লোন বিল্ডের প্রত্যাশিত আচরণ।',
      'honest.i5': '<strong>এটি একটি বেটা।</strong> কিছু অদ্ভুত আচরণ করলে Issues-এ আপনার Windows ভার্সন, কোন ফাইল নেমেছেন এবং About বক্সের ভার্সন লিখে জানান।',

      'tl.1.title': 'অফিসিয়াল সর্বশেষ রিলিজ — Avro Keyboard 5.6.0',
      'tl.1.body': 'এরপর অফিসিয়াল কোনো নতুন ভার্সন আসেনি। আজও OmicronLab.com-এ এটিই সর্বশেষ ডাউনলোড।',
      'tl.2.title': 'ক্যানোনিকাল সোর্স রিপো read-only',
      'tl.2.body': 'অফিসিয়াল সোর্সের মূল রিপোটি archive করা হয় — অর্থাৎ উইন্ডোজের নতুন সংস্করণের সমস্যাগুলো আর কেউ ঠিক করছিল না।',
      'tl.3.title': 'Community Edition-এর সোর্স শুরু',
      'tl.3.body': 'MPL-2.0 লাইসেন্সের আওতায় সেই ওপেন সোর্স কোড থেকে আলাদা রক্ষণাবেক্ষণ শুরু — পুরো ইতিহাস ও আপস্ট্রিম বেসলাইন অক্ষত রেখে।',
      'tl.4.title': 'প্রথম পাবলিক বিল্ড — 6.0.2-beta',
      'tl.4.body': 'নেটিভ ৬৪/৩২-বিট ইনস্টলার ও পোর্টেবল, নতুন ANSI ইঞ্জিন, ইন-অ্যাপ কনভার্টার, রিসোর্স ব্রাউজার ও অটো আপডেট — সব একসাথে।',
      'tl.when1': '27 আগস্ট 2019', 'tl.when2': '9 আগস্ট 2026', 'tl.when3': '15 অক্টোবর 2026', 'tl.when4': '16 অক্টোবর 2026',

      'features.kicker': 'কী আছে ভেতরে',
      'features.h2': 'যে বিষয়গুলো <span class="gradient">প্রতিদিনের টাইপিংয়ে</span> পার্থক্য গড়ে',
      'features.lead': 'প্রতিটি পয়েন্টই 6.0.2-beta-এর release notes বা এই রিপোর Readme-তে লেখা আছে।',
      'feature.1.title': 'নেটিভ 64 ও 32-bit',
      'feature.1.body': 'দুই আর্কিটেকচারের জন্য আলাদা বিল্ড। বড় ডকুমেন্ট আর দীর্ঘ সেশনে ৬৪-বিট বিল্ড বেশি স্থিতিশীল।',
      'feature.2.title': 'সত্যিকারের পোর্টেবল',
      'feature.2.body': 'সেটিংস exe-এর পাশেই, ডেটা ফোল্ডারের ভেতরেই। USB থেকে চালান, শেষে ফোল্ডার মুছে দিন।',
      'feature.3.title': 'ফাইল-ভিত্তিক ANSI ইঞ্জিন',
      'feature.3.body': 'V1–V5 প্রতিটি এনকোডিং আলাদা ফাইল থেকে লোড হয় — আর কোনো হার্ডকোডেড ম্যাপিং নেই।',
      'feature.4.title': 'স্টার্টআপ কখনো নীরবে ব্যর্থ হয় না',
      'feature.4.body': 'প্রতিটি ধাপ সুরক্ষিত, সাথে দৃশ্যমান রিপোর্ট ও <code>AvroStartup.log</code>।',
      'feature.5.title': 'SHA-256 যাচাইসহ ডাউনলোড',
      'feature.5.body': 'রিসোর্স ও আপডেট — দুই ক্ষেত্রেই ফাইল হ্যাশ মিলে গেলেই ইনস্টল হয়।',
      'feature.6.title': 'Grapheme-aware ব্যাকস্পেস',
      'feature.6.body': 'যৌগিক অক্ষর আর ভেঙে একক মাত্রা পড়ে থাকে না — পুরো অক্ষর-গ্রুপ একবারে মুছে।',

      'install.kicker': 'শুরু করা',
      'install.h2': 'তিন ধাপে বাংলা টাইপিং',
      'install.lead': 'ডাউনলোড থেকে বাংলা লেখা — ইনস্টলার অথবা পোর্টেবল, যেটা আপনার সুবিধা।',
      'install.s1.title': 'আমাদের কমিউনিটি সংস্করণ ডাউনলোড করুন',
      'install.s1.body': 'নিচের কার্ডগুলো থেকে আপনার উইন্ডোজ আর্কিটেকচার অনুযায়ী সঠিক ইনস্টলার অথবা পোর্টেবল জিপ (ZIP) ফাইলটি বেছে নিন।',
      'install.s2.title': 'ইনস্টল বা extract করুন',
      'install.s2.body': 'ইনস্টল করতে চাইলে সেটআপ ফাইলটি চালান; অন্যথায় জিপ (ZIP) ফাইলটি এক্সট্র্যাক্ট করে সরাসরি ফোল্ডার থেকেই ব্যবহার করুন — পোর্টেবল সংস্করণের জন্য কোনো ইনস্টলেশনের প্রয়োজন নেই।',
      'install.s3.title': 'বাংলা টাইপ শুরু করুন',
      'install.s3.body': 'ট্রে আইকন থেকে Avro Phonetic নির্বাচন করুন। এরপর ডিকশনারি মোড (dictionary mode) সিলেক্ট করুন। তারপর <strong>MS Word বা Notepad</strong> খুলুন।',

      'download.kicker': 'ডাউনলোড ও আর্কাইভ',
      'download.h2': 'Avro Keyboard রিলিজ',
      'download.lead': 'কার্ডগুলো GitHub releases API থেকে লাইভ আসে। এখনো মাত্র একটি বিল্ড হয়েছে, তাই গ্রিডটি পূরণ করতে অফিসিয়াল 5.6.0 বেসলাইন কার্ডও দেখানো হচ্ছে।',
      'download.filters': 'রিলিজ ফিল্টার',
      'download.filter.all': 'সব রিলিজ',
      'download.filter.installer': 'ইনস্টলার',
      'download.filter.portable': 'পোর্টেবল',
      'download.filter.official': 'অফিসিয়াল',
      'download.note': 'প্রতিটি রিলিজের বিস্তারিত নোট ও SHA-256 <a href="changelog.html">চেঞ্জলগ পেজে</a> আছে।',
      'cta.kicker': 'বাংলা ছড়িয়ে পড়ুক',
      'cta.h2': 'ভাষা হোক উন্মুক্ত।',
      'cta.body': 'বাগ রিপোর্ট করুন, কোড অবদান রাখুন, অথবা কমিউনিটিতে যোগ দিন — সবটাই স্বাগত।',
      'cta.button': '<i class="fa-brands fa-github" aria-hidden="true"></i> GitHub-এ রিপো দেখুন <i class="fa-solid fa-arrow-up-right-from-square" aria-hidden="true"></i>',

      /* ---- changelog.html ---- */
      'cl.meta.title': 'রিলিজ চেঞ্জলগ — Avro Keyboard Community Edition',
      'cl.meta.desc': 'Avro Keyboard Community Edition-এর প্রতিটি রিলিজের পূর্ণ changelog — কী নতুন, কী ঠিক হয়েছে, ফাইল তালিকা ও SHA-256। GitHub releases API থেকে লাইভ।',
      'cl.crumb': 'চেঞ্জলগ',
      'cl.h1': 'প্রতিটি রিলিজের <span class="gradient">পূর্ণ চেঞ্জলগ</span>',
      'cl.lead': 'প্রতিটি রিলিজের নোট, ডাউনলোড ফাইল, সাইজ, ডাউনলোড সংখ্যা ও SHA-256 — সবই GitHub releases API থেকে লাইভ আনা হয়। নতুন রিলিজ প্রকাশ করলে এই পেজে নিজে থেকেই যুক্ত হয়ে যাবে; কিছু হাতে বদলাতে হবে না।',

      /* ---- privacy.html ---- */
      'pv.meta.title': 'প্রাইভেসি পলিসি — Avro Keyboard Community Edition',
      'pv.meta.desc': 'Avro Keyboard Community Edition ওয়েবসাইট ও ডেস্কটপ অ্যাপের প্রাইভেসি পলিসি — কোন ডেটা কোথায় থাকে, কী সংগ্রহ করা হয় না, এবং সব মুছে ফেলার উপায়।',
      'pv.crumb': 'প্রাইভেসি',
      'pv.h1': 'প্রাইভেসি <span class="gradient">পলিসি</span>',
      'pv.lead': 'এই ডকুমেন্ট দুটি আলাদা জিনিস কভার করে — প্রথমে এই ওয়েবসাইটটি, তারপর Avro Keyboard Community Edition ডেস্কটপ অ্যাপটি। দুটোতেই যা সত্যিই ঘটে, তাই লেখা আছে।',
      'pv.toc.heading': 'সূচিপত্র',
      'pv.toc.summary': 'সংক্ষেপে',
      'pv.toc.website': 'ওয়েবসাইট',
      'pv.toc.storage': 'ব্রাউজারে যা থাকে',
      'pv.toc.noCollect': 'যা করা হয় না',
      'pv.toc.links': 'বাইরের লিংক',
      'pv.toc.app': 'ডেস্কটপ অ্যাপের ডেটা',
      'pv.toc.log': 'AvroStartup.log',
      'pv.toc.network': 'অ্যাপের নেটওয়ার্ক ব্যবহার',
      'pv.toc.remove': 'সব মুছে ফেলা',
      'pv.toc.contact': 'পরিবর্তন ও যোগাযোগ',
      'pv.meta.line': '<strong>সর্বশেষ আপডেট:</strong> 16 অক্টোবর 2026 · <strong>প্রযোজ্য:</strong> এই ওয়েবসাইট এবং Avro Keyboard Community Edition ডেস্কটপ বিল্ড',
      'pv.summary.h': 'সংক্ষেপে',
      'pv.summary.callout': 'সংক্ষেপে বললে — <strong>না</strong> অ্যাকাউন্ট, <strong>না</strong> কুকি, <strong>না</strong> অ্যানালিটিক্স, <strong>না</strong> বিজ্ঞাপন, <strong>না</strong> ট্র্যাকিং। আমরা আপনার কাছ থেকে কোনো ব্যক্তিগত তথ্য চাই না এবং পাইও না। ডেস্কটপ অ্যাপটি কোনো টেলিমেট্রি পাঠায় না, আর আপনার টাইপ করা লেখা কোথাও জমা রাখে না।',
      'pv.summary.p': 'একমাত্র নেটওয়ার্ক যোগাযোগ হয় আপনার নিজের ব্রাউজার থেকে GitHub-এর পাবলিক API-তে, এবং অ্যাপে আপনার নিজের অনুরোধে (রিসোর্স বা আপডেট নামানোর সময়) GitHub Releases থেকে।',
      'pv.website.h': '⓵ এই ওয়েবসাইটে কী ঘটে',
      'pv.website.hosting.h': 'হোস্টিং',
      'pv.website.hosting.p': 'সাইটটি <strong>GitHub Pages</strong>-এ হোস্ট করা একটি স্ট্যাটিক সাইট। আমরা নিজেরা কোনো সার্ভার চালাই না, কোনো ডেটাবেজ রাখি না এবং কোনো লগ সংরক্ষণ করি না। তবে যেকোনো ওয়েব হোস্টিংয়ের মতো GitHub তাদের নিজের সিস্টেম লগে ভিজিটরের IP অ্যাড্রেস, ব্রাউজার/ডিভাইসের তথ্য এবং অনুরোধের সময় সংরক্ষণ করতে পারে। সেই লগ GitHub-এর নিয়ন্ত্রণে, আমাদের নয় — বিস্তারিত <a href="https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement" target="_blank" rel="noopener noreferrer">GitHub-এর প্রাইভেসি স্টেটমেন্টে</a>।',
      'pv.website.api.h': 'লাইভ ডেটার জন্য API কল',
      'pv.website.api.p': 'পেজের কাউন্টার, রিলিজ কার্ড ও চেঞ্জলগ লোড করতে <strong>আপনার ব্রাউজার</strong> সরাসরি <code>api.github.com</code>-এ অনুরোধ পাঠায়। ফলাফল:',
      'pv.website.api.li1': 'আপনার IP অ্যাড্রেস GitHub পর্যন্ত পৌঁছায় — ঠিক যেভাবে এই সাইটটি লোড হওয়ার সময়ই GitHub Pages পর্যন্ত পৌঁছেছে।',
      'pv.website.api.li2': 'আমরা শুধু <em>পাবলিক</em> রিপো ও রিলিজের তথ্য চাই — আপনি কে বা আপনার কী পরিচয়, তা কোথাও পাঠানো হয় না।',
      'pv.website.api.li3': 'কোনো API টোকেন, লগইন বা কুকি ব্যবহার হয় না; অনুরোধ সম্পূর্ণ অ্যানোনিমাস।',
      'pv.website.api.li4': 'কোনো প্রোফাইলিং হয় না — এই ডেটা আমাদের কাছে কোথাও জমা হয় না, কারণ জমা রাখার কোনো সার্ভারই নেই।',
      'pv.storage.h': '⓶ আপনার ব্রাউজারে যা সংরক্ষিত থাকে',
      'pv.storage.p': 'সাইটটি শুধু <code>localStorage</code> ব্যবহার করে — কোনো cookies নয়। নিচের কীগুলো আপনার ব্রাউজারেই থাকে এবং শুধু আপনার পরবর্তী ভিজিটে কাজে লাগে:',
      'pv.storage.th.key': 'কী (key)',
      'pv.storage.th.what': 'কী থাকে',
      'pv.storage.th.why': 'কেন',
      'pv.storage.tr1.what': 'শুধু <code>light</code> অথবা <code>dark</code>',
      'pv.storage.tr1.why': 'আপনি যে থিম বেছে নেন, সেটি পরের পেজ লোডেও রাখতে',
      'pv.storage.tr2.what': 'GitHub API থেকে পাওয়া পাবলিক ডেটার ক্যাশ (রিপো স্ট্যাট, রিলিজ তালিকা) ও তার সময়',
      'pv.storage.tr2.why': 'একই ডেটা বারবার না আনতে, এবং API-এর ঘণ্টায়-সীমা বাঁচাতে',
      'pv.storage.tr3.what': 'শেষবার পাওয়া পাবলিক ডেটার স্ন্যাপশট (রিপো স্ট্যাট, রিলিজ, অফিসিয়াল বেসলাইন) ও কখন নেওয়া হয়েছিল',
      'pv.storage.tr3.why': 'GitHub API পরে সাড়া না দিলেও যেন আসল সংখ্যাগুলোই দেখানো যায় — সাইটের সঙ্গে দেওয়া স্ন্যাপশটের চেয়ে নতুন ডেটা',
      'pv.storage.tr4.what': 'আপনি যে ভাষা বেছেছেন — <code>en</code> অথবা <code>bn</code>',
      'pv.storage.tr4.why': 'পরের পেজ লোডেও আপনার বেছে নেওয়া ভাষাতেই দেখাতে',
      'pv.storage.note': 'এই স্টোরেজে ব্যক্তিগত কোনো তথ্য নেই — এগুলো সেই একই পাবলিক সংখ্যা যা যে কেউ GitHub-এ দেখতে পায়। ক্যাশ সাধারণত ১০ মিনিট পর নিজে থেকেই বাতিল হয়, আর স্ন্যাপশট পরের ভিজিটে নতুন ডেটা দিয়ে আপডেট হয়ে যায়।',
      'pv.noCollect.h': '⓷ যা আমরা করি না',
      'pv.noCollect.li1': '<strong>কোনো অ্যানালিটিক্স নেই</strong> — Google Analytics বা অনুরূপ কোনো টুল নেই।',
      'pv.noCollect.li2': '<strong>কোনো ট্র্যাকিং বা ফিঙ্গারপ্রিন্টিং নেই</strong> — কোনো পিক্সেল, বিটা বা স্ক্রিপ্ট নয়।',
      'pv.noCollect.li3': '<strong>কোনো বিজ্ঞাপন নেই</strong>, কোনো অ্যাড নেটওয়ার্কও নেই।',
      'pv.noCollect.li4': '<strong>কোনো ফর্ম বা অ্যাকাউন্ট নেই</strong> — সাইন-আপ, নিউজলেটার বা ইমেইল সংগ্রহ নেই।',
      'pv.noCollect.li5': '<strong>কোনো তৃতীয় পক্ষ নেই</strong> — কোনো CDN, ফন্ট সার্ভার বা সোশ্যাল বাটন বাইরে থেকে লোড হয় না; ফন্টও এই সাইটের ভেতর থেকেই আসে।',
      'pv.noCollect.li6': '<strong>কোনো ডেটা বিক্রি বা শেয়ার নেই</strong> — কারণ আমাদের কাছে বিক্রি করার মতো কোনো ডেটাই নেই।',
      'pv.links.h': '⓸ বাইরের লিংক',
      'pv.links.p': 'পেজে এমন কিছু লিংক আছে যা এই সাইটের বাইরে যায়। সেগুলোতে ক্লিক করলে আপনি সেই সাইটের নিজস্ব নীতির আওতায় চলে যাবেন — আমরা তার জন্য দায়ী নই:',
      'pv.links.li1': '<strong>github.com</strong> — সোর্স কোড, রিলিজ ডাউনলোড, ইস্যু ট্র্যাকিং ও API।',
      'pv.links.li2': '<strong>OmicronLab.com</strong> — অফিসিয়াল Avro Keyboard-এর পুরোনো ভার্সন ডাউনলোড ও তথ্য।',
      'pv.links.li3': '<strong>t.me/AvroUsersCommunity</strong> — কমিউনিটির Telegram গ্রুপ।',
      'pv.links.p2': 'বাইরের সব লিংক নতুন ট্যাবে ও <code>rel="noopener noreferrer"</code> দিয়ে খোলে।',
      'pv.app.h': '⓹ ডেস্কটপ অ্যাপ: ডেটা কোথায় থাকে',
      'pv.app.p': 'অ্যাপটি আপনার কম্পিউটারেই সব ডেটা রাখে। কোথায় রাখে, সেটা নির্ভর করে আপনি কোন এডিশন চালাচ্ছেন তার উপর:',
      'pv.app.th.edition': 'এডিশন',
      'pv.app.th.settings': 'সেটিংস',
      'pv.app.th.data': 'ডেটা (ডেটাবেজ, ম্যাপিং, লেআউট, স্কিন, লগ)',
      'pv.app.tr1.edition': 'Standard (ইনস্টল করা)',
      'pv.app.tr1.data': '<code>%ProgramData%\\Avro Keyboard\\</code>',
      'pv.app.tr2.edition': 'Portable',
      'pv.app.tr2.settings': 'exe-এর পাশে <code>Settings.xml</code>',
      'pv.app.tr2.data': 'যে ফোল্ডারে <code>Avro Keyboard.exe</code> আছে',
      'pv.app.p2': 'উভয় এডিশনই রেজিস্ট্রিতে তিনটি এন্ট্রি লেখে — “কোনো রেজিস্ট্রি পরিবর্তন হয় না” বলা ঠিক হবে না:',
      'pv.app.li1': '<code>HKCU\\Control Panel\\Desktop\\LowLevelHooksTimeout</code> (5000 ms) — যাতে অন্য কোনো অ্যাপ কিছু সময় আটকে দিলে Windows নীরবে কীবোর্ড হুক ফেলে না দেয়।',
      'pv.app.li2': 'পোর্টেবল Siyam Rupali ফন্ট নিবন্ধিত থাকা অবস্থায় দুটি IE ফন্ট মান (<code>IEFixedFontName</code>, <code>IEPropFontName</code>) — আগের মানগুলো <code>_Prev</code> এন্ট্রিতে সংরক্ষিত থাকে এবং ফন্ট সরালে আগের অবস্থায় ফিরে যায়।',
      'pv.app.p3': 'পোর্টেবল এডিশনে সিস্টেম-ওয়াইড কিছুই ইনস্টল বা রেজিস্টার হয় না; ফোল্ডারটি যেকোনো সময় সরানো বা মুছে ফেলা যায়।',
      'pv.log.h': '⓺ AvroStartup.log — কী লেখা থাকে, কী থাকে না',
      'pv.log.p': 'অ্যাপ চালু হওয়ার সময় সমস্যা হলে যেন নীরবে বন্ধ না হয়ে যায়, সেজন্য একটি ডায়াগনস্টিক লগ লেখা হয়। এতে থাকে: স্টার্টআপের ধাপগুলো, কোন এডিশন চলছে, exe ও ডেটা ফোল্ডারের পাথ, ফোল্ডারে লেখা যায় কি না, ডেটাবেজ ফাইলের সাইজ ও পরিবর্তনের সময়, Windows বিল্ড নম্বর, এবং কোনো ধাপ ব্যর্থ হলে সেই exception-এর ক্লাস ও মেসেজ।',
      'pv.log.callout': '<strong>এই লগে কখনো আপনার টাইপ করা লেখা থাকে না।</strong> কোনো keystroke, কোনো শব্দ বা কোনো লেখা এতে রেকর্ড হয় না — রানটাইমে সর্বোচ্চ যা লেখা হয় তা হলো exception-এর ক্লাস। ডিবাগ লগ (<code>Log()</code>) শুধু ডিবাগারে লেখে, কখনো ফাইলে নয়।',
      'pv.log.p2': 'লগটি ডেটা ফাইলের পাশেই থাকে এবং 256 KB ছাড়ালে <code>AvroStartup.log.old</code>-এ রোটেট হয়। ডেটা ফোল্ডারে লেখা না গেলে এটি <code>%LOCALAPPDATA%\\AvroKeyboard\\</code>, তারপর <code>%TEMP%\\AvroKeyboard\\</code>-এ যায়; কোথাও লেখা না গেলে লগটি নীরবে বাদ পড়ে — স্টার্টআপ কখনো লগের উপর নির্ভর করে না।',
      'pv.network.h': '⓻ অ্যাপ কখন নেটওয়ার্ক ব্যবহার করে',
      'pv.network.p': 'অ্যাপটি নিজে থেকে কোথাও কিছু পাঠায় না। নেটওয়ার্ক ব্যবহার হয় কেবল তখনই, যখন <strong>আপনি নিজে</strong> কোনো কিছু নামাতে বলেন:',
      'pv.network.li1': 'ট্রে মেনুর <strong>“Download Resources”</strong> থেকে লেআউট, স্কিন বা ANSI ম্যাপিং প্যাক নামানো।',
      'pv.network.li2': 'ইন-অ্যাপ <strong>অটো আপডেট</strong> দিয়ে নতুন বিল্ড নামানো।',
      'pv.network.p2': 'দুটো ক্ষেত্রেই অনুরোধ যায় GitHub-এ, এবং নামানো প্রতিটি ফাইল ইনস্টল হওয়ার আগে <strong>SHA-256</strong> দিয়ে যাচাই করা হয়। কোনো ক্র্যাশ রিপোর্ট, ব্যবহারের পরিসংখ্যান বা ব্যক্তিগত সনাক্তকারী কোথাও পাঠানো হয় না।',
      'pv.remove.h': '⓼ সব ডেটা মুছে ফেলা',
      'pv.remove.p': 'আপনার মেশিনে অ্যাপের যাবতীয় চিহ্ন সরাতে:',
      'pv.remove.li1': '<strong>Portable:</strong> ফোল্ডারটি মুছে ফেলুন, তারপরেই <code>HKCU\\Control Panel\\Desktop\\LowLevelHooksTimeout</code> এন্ট্রিটি মুছে দিন।',
      'pv.remove.li2': '<strong>Standard:</strong> আনইনস্টল করুন, তারপর <code>%ProgramData%\\Avro Keyboard\\</code> ফোল্ডার এবং <code>HKEY_CURRENT_USER\\Software\\OmicronLab\\Avro Keyboard</code> কী-টি মুছে দিন।',
      'pv.remove.li3': '<strong>আপডেট ফোল্ডার:</strong> অটো আপডেট ব্যবহার করলে ডাউনলোড করা প্যাকেজ ডেটা ফোল্ডারের ভেতরে থাকতে পারে — পুরো ডেটা ফোল্ডার মুছে দিলে সেটিও চলে যাবে।',
      'pv.remove.li4': '<strong>এই ওয়েবসাইট:</strong> ব্রাউজার সেটিংস থেকে <code>avro-gh-v1</code>, <code>avro-snap-v1</code>, <code>avro-lang</code> ও <code>avro-theme</code> কীগুলো মুছে দিন, অথবা সাইটের ডেটা সাফ করুন।',
      'pv.remove.li5': '<strong>লগ:</strong> <code>AvroStartup.log</code> ও <code>AvroStartup.log.old</code> ফাইল দুটিও ডেটা ফোল্ডারে থাকে — সাথেই মুছে যাবে।',
      'pv.contact.h': '⓽ পরিবর্তন, যোগাযোগ ও লাইসেন্স',
      'pv.contact.p1': 'এই নীতিতে পরিবর্তন এলে এই পেজেই হালনাগাদ করা হবে এবং উপরের “সর্বশেষ আপডেট” তারিখ বদলে যাবে। এই সাইটটি কোনো ব্যক্তিগত তথ্য সংগ্রহ করে না, তাই কোনো তথ্য-অনুরোধের প্রক্রিয়াও নেই।',
      'pv.contact.p2': 'কোনো প্রশ্ন, সংশোধনী বা উদ্বেগ থাকলে GitHub Issues-এ জানাতে পারেন: <a href="https://github.com/raselrahmanrocky/Avro-Keyboard/issues" target="_blank" rel="noopener noreferrer">raselrahmanrocky/Avro-Keyboard/issues <i class="fa-solid fa-arrow-up-right-from-square" aria-hidden="true"></i></a>',
      'pv.contact.p3': 'Avro Keyboard Community Edition একটি স্বতন্ত্র কন্টিনিউয়েশন — MPL-2.0 লাইসেন্সের আওতায় Avro Keyboard-এর ওপেন সোর্স কোড থেকে তৈরি। <strong>OmicronLab বা এর মূল ডেভেলপারদের সঙ্গে সম্পৃক্ত নয়</strong> এবং তারা এটির সমর্থন করে না। মূল সোর্স ও কপিরাইট OmicronLab (Mehdi Hasan Khan)-এর। Qt কনভার্টার Qt-এর LGPLv3 শর্তে চলে।'
    }
  };

  /* ------------------------------------------------------------- helpers -- */
  function normalize(value) {
    var v = String(value || '').toLowerCase().slice(0, 2);
    return SUPPORTED.indexOf(v) !== -1 ? v : null;
  }

  function readStored() {
    try { return normalize(localStorage.getItem(STORE_KEY)); } catch (e) { return null; }
  }

  function fromQuery() {
    try { return normalize(new URLSearchParams(location.search).get('lang')); } catch (e) { return null; }
  }

  function persist(locale) {
    try { localStorage.setItem(STORE_KEY, locale); } catch (e) { /* private mode */ }
  }

  /* The value the pre-paint script in <head> already resolved, if any. */
  function initial() {
    return normalize(document.documentElement.getAttribute('data-lang')) || DEFAULT;
  }

  var current = initial();

  function intlTag(map) {
    return map[current] || map[DEFAULT];
  }

  function interpolate(text, vars) {
    if (!vars) return text;
    return String(text).replace(/\{(\w+)\}/g, function (whole, name) {
      return Object.prototype.hasOwnProperty.call(vars, name) ? String(vars[name]) : whole;
    });
  }

  /** Pick the active language's variant of an { en, bn } editorial value. */
  function pick(value) {
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      if (typeof value[current] === 'string') return value[current];
      if (typeof value.en === 'string') return value.en;
    }
    return typeof value === 'string' ? value : '';
  }

  /** A string the JavaScript layer renders, in the active language. */
  function t(key, vars) {
    var table = dict[current] || {};
    var text = Object.prototype.hasOwnProperty.call(table, key) ? table[key] : null;
    if (text === null && dict.en && Object.prototype.hasOwnProperty.call(dict.en, key)) {
      text = dict.en[key];
    }
    if (text === null) {
      /* A missing key is a bug, but it must never blank the interface. */
      if (window.console && console.warn) console.warn('[i18n] missing key: ' + key);
      text = key;
    }
    return interpolate(text, vars);
  }

  /**
   * A counted phrase, with English singular handling: a key of `n` selects
   * `key + '.one'` when that exists in the active language. Bangla needs no
   * plural branch — "3 টি" and "1 টি" follow the same pattern — so its
   * dictionary simply keeps the same text under both keys.
   */
  function tn(n, key, vars) {
    var table = dict[current] || {};
    var full = (n === 1 && Object.prototype.hasOwnProperty.call(table, key + '.one'))
      ? key + '.one'
      : key;
    return t(full, vars);
  }

  /* --------------------------------------------------- DOM prose swapping -- */
  /* English is captured from the document the first time we look, so the
     shipped HTML stays the single source of the default language. */
  var captured = Object.create(null);
  var bound = [];

  function eachKeyed(fn) {
    var nodes = document.querySelectorAll('[data-i18n]');
    for (var i = 0; i < nodes.length; i++) fn(nodes[i], 'data-i18n', 'html');
    for (var a = 0; a < ATTRS.length; a++) {
      var attr = ATTRS[a];
      var sel = '[data-i18n-' + attr + ']';
      var found = document.querySelectorAll(sel);
      for (var j = 0; j < found.length; j++) fn(found[j], 'data-i18n-' + attr, attr);
    }
  }

  function capture() {
    eachKeyed(function (el, marker, slot) {
      var key = el.getAttribute(marker);
      if (!key) return;
      var storeKey = slot + '|' + key;
      if (Object.prototype.hasOwnProperty.call(captured, storeKey)) return;
      var value = slot === 'html' ? el.innerHTML : el.getAttribute(slot);
      if (value === null) return;
      captured[storeKey] = value;
      bound.push({ el: el, key: key, slot: slot, storeKey: storeKey });
    });
  }

  function write(el, slot, value) {
    if (value === null || value === undefined) return;
    if (slot === 'html') el.innerHTML = value;
    else el.setAttribute(slot, value);
  }

  /* Elements can be replaced wholesale by a re-render, so re-query rather
     than reusing the first pass's node list. */
  function apply() {
    capture();
    var table = dict[current] || {};
    bound = [];
    eachKeyed(function (el, marker, slot) {
      var key = el.getAttribute(marker);
      if (!key) return;
      var storeKey = slot + '|' + key;
      var english = captured[storeKey];
      var translated = Object.prototype.hasOwnProperty.call(table, key) ? table[key] : null;
      write(el, slot, translated !== null ? translated : english);
      bound.push({ el: el, key: key, slot: slot, storeKey: storeKey });
    });
  }

  /* ------------------------------------------------------------- library -- */
  function refreshChrome() {
    var root = document.documentElement;
    root.setAttribute('lang', current);
    root.setAttribute('data-lang', current);
    root.removeAttribute('data-i18n-pending');

    /* Social previews and search snippets follow the chosen language. */
    var og = document.querySelector('meta[property="og:locale"]');
    if (og) og.setAttribute('content', current === 'bn' ? 'bn_BD' : 'en_US');

    var ogTitle = document.querySelector('meta[property="og:title"]');
    var docTitle = document.title;
    if (ogTitle && docTitle) ogTitle.setAttribute('content', docTitle);

    var ogDesc = document.querySelector('meta[property="og:description"]');
    var desc = document.querySelector('meta[name="description"]');
    if (ogDesc && desc) ogDesc.setAttribute('content', desc.getAttribute('content') || '');
  }

  function paintSwitcher() {
    var toggles = document.querySelectorAll('[data-lang-toggle]');
    for (var i = 0; i < toggles.length; i++) {
      var codes = toggles[i].querySelectorAll('[data-lang-code]');
      for (var j = 0; j < codes.length; j++) {
        var active = codes[j].getAttribute('data-lang-code') === current;
        codes[j].setAttribute('data-active', active ? 'true' : 'false');
      }
      /* The pill announces the language a click will switch to. */
      var target = current === 'bn' ? 'en' : 'bn';
      toggles[i].setAttribute('title', LABELS[target].native);
      toggles[i].setAttribute('aria-label', LABELS[target].native);
    }
  }

  function announce() {
    try {
      document.dispatchEvent(new CustomEvent('avro:locale', { detail: { locale: current } }));
    } catch (e) { /* very old browsers: modules then simply keep their copy */ }
  }

  function setLocale(next, opts) {
    var target = normalize(next);
    if (!target || target === current) {
      if (target) persist(target);
      return false;
    }
    persist(target);
    current = target;

    /* Keep the chosen language in the URL so the page stays shareable and
       reloadable in that language. */
    if (!opts || opts.updateUrl !== false) {
      try {
        var url = new URL(location.href);
        url.searchParams.set('lang', target);
        history.replaceState(null, '', url.toString());
      } catch (e) { /* file:// or a blocked history API */ }
    }

    apply();
    paintSwitcher();
    refreshChrome();
    announce();
    return true;
  }

  /* The language the head script resolved is already in the DOM attribute, so
     an explicit choice in the URL wins over whatever is stored. */
  function boot() {
    var wanted = fromQuery() || readStored() || DEFAULT;
    if (wanted !== current) {
      current = wanted;
      persist(wanted);
    }
    apply();
    paintSwitcher();
    refreshChrome();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

  /* One delegated listener covers every page's switcher. */
  document.addEventListener('click', function (event) {
    var toggle = event.target.closest ? event.target.closest('[data-lang-toggle]') : null;
    if (!toggle) return;
    event.preventDefault();
    setLocale(current === 'bn' ? 'en' : 'bn');
  });

  return {
    SUPPORTED: SUPPORTED,
    DEFAULT: DEFAULT,
    LABELS: LABELS,
    locale: function () { return current; },
    dateLocale: function () { return intlTag(INTL_DATE); },
    relativeLocale: function () { return intlTag(INTL_REL); },
    t: t,
    tn: tn,
    pick: pick,
    apply: apply,
    setLocale: setLocale,
    dict: dict
  };
})();
