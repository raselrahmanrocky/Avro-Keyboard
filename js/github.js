/* ==========================================================================
   GitHub data layer.

   Everything this site shows about the project comes from the public GitHub
   API. Because anonymous API access is rate limited (60 requests/hour per
   visitor IP), each page paints from a snapshot first and then refreshes from
   the API. Any failure keeps whatever is already on screen.

   Snapshots have two layers (see js/snapshot.js): the one saved on an earlier
   visit, which real live responses keep updating, and the one committed in
   data/ which ships with the site. So a rate-limited or offline visitor still
   sees genuine project data, and every reader reports which layer it used.
   ========================================================================== */
window.AVRO_GH = (function () {
  'use strict';

  var cfg = window.AVRO;
  var SRC = cfg.source;
  var OFF = cfg.official;
  var SLUG = SRC.owner + '/' + SRC.repo;

  var SNAP = window.AVRO_SNAP || null;

  /* Read lazily: the layers above are loaded as separate files, and a missing
     one must degrade into readable English rather than break the page. */
  function T(key, vars) {
    var i18n = window.AVRO_I18N;
    return i18n ? i18n.t(key, vars) : key;
  }

  function pick(value) {
    var i18n = window.AVRO_I18N;
    return i18n ? i18n.pick(value) : (typeof value === 'string' ? value : '');
  }

  /* A local fixture server can stand in for the API, but only on loopback, so
     a crafted link can never point a real visitor at a different API host. */
  var params = new URLSearchParams(location.search);
  var isLoopback = location.hostname === 'localhost' ||
                   location.hostname === '127.0.0.1' ||
                   location.protocol === 'file:';
  var override = isLoopback ? params.get('apiBase') : null;
  var BASE = (override ? override : 'https://api.github.com').replace(/\/+$/, '');

  var U = {
    repo: BASE + '/repos/' + SLUG,
    commits: BASE + '/repos/' + SLUG + '/commits?per_page=1',
    contributors: BASE + '/repos/' + SLUG + '/contributors',
    compare: BASE + '/repos/' + SLUG + '/compare/' + SRC.baseline + '...' + SRC.branch,
    releases: BASE + '/repos/' + SLUG + '/releases?per_page=10',
    official: BASE + '/repos/' + OFF.owner + '/' + OFF.repo,
    commitsFor: function (tag) {
      return BASE + '/repos/' + SLUG + '/commits?sha=' + encodeURIComponent(tag) + '&per_page=100';
    },
    compareTags: function (a, b) {
      return BASE + '/repos/' + SLUG + '/compare/' + encodeURIComponent(a) + '...' + encodeURIComponent(b);
    }
  };

  /* ---------------------------------------------------------------- cache -- */
  var MAX_CACHE_BYTES = 120000;
  var MAX_CACHE_ENTRIES = 40;
  var inflight = Object.create(null);
  var memo = Object.create(null);
  var store = null;

  /* Composite reads are memoised for the life of the page so two modules
     asking for the same data never spend two rounds of API calls. */
  function once(key, factory) {
    if (!memo[key]) memo[key] = factory();
    return memo[key];
  }

  /* One shared store for the whole page. Reading a fresh copy per request
     would let concurrent responses overwrite each other, so only the last
     entry written would ever survive. */
  function getStore() {
    if (store) return store;
    try {
      var parsed = JSON.parse(localStorage.getItem(cfg.cacheKey) || 'null');
      if (parsed && parsed.entries) store = parsed;
    } catch (e) { /* storage disabled or corrupt — fall through */ }
    if (!store) store = { entries: {} };
    return store;
  }

  function writeCache() {
    try {
      localStorage.setItem(cfg.cacheKey, JSON.stringify(getStore()));
    } catch (e) {
      /* quota or private mode: caching is an optimisation, never required */
    }
  }

  function remember(url, entry) {
    var current = getStore();
    current.entries[url] = entry;

    /* Bound the store by dropping the oldest entries first. */
    var keys = Object.keys(current.entries);
    if (keys.length > MAX_CACHE_ENTRIES) {
      keys.sort(function (a, b) {
        return (current.entries[a].t || 0) - (current.entries[b].t || 0);
      }).slice(0, keys.length - MAX_CACHE_ENTRIES).forEach(function (key) {
        delete current.entries[key];
      });
    }

    writeCache();
  }

  /**
   * GET a GitHub API URL. Returns { data, link, cached }.
   * @param {string} url
   * @param {{cache?: boolean}} [opts]
   */
  async function get(url, opts) {
    var useCache = !opts || opts.cache !== false;
    var hit = getStore().entries[url];

    if (useCache && hit && (Date.now() - hit.t) < cfg.ttl) {
      return { data: hit.data, link: hit.link, cached: true };
    }

    /* Concurrent callers share one request instead of spending two of the
       visitor's hourly API allowance on the same URL. */
    if (inflight[url]) return inflight[url];

    var request = (async function () {
      try {
        var res = await fetch(url, { headers: { Accept: 'application/vnd.github+json' } });
        if (!res.ok) {
          var err = new Error('GitHub API ' + res.status + ' for ' + url);
          err.status = res.status;
          throw err;
        }

        var data;
        try {
          data = await res.json();
        } catch (e) {
          throw new Error('GitHub API returned malformed JSON for ' + url);
        }

        var link = res.headers.get('Link') || null;

        if (useCache) {
          var probe = JSON.stringify(data);
          if (probe.length <= MAX_CACHE_BYTES) {
            remember(url, { t: Date.now(), data: data, link: link });
          }
        }
        return { data: data, link: link, cached: false };
      } finally {
        /* Never let a failed request poison later callers. */
        delete inflight[url];
      }
    })();

    inflight[url] = request;
    return request;
  }

  /** The snapshot committed in data/, which ships with the site. */
  async function committed(name) {
    try {
      var res = await fetch('data/' + name + '.json', { cache: 'no-cache' });
      if (!res.ok) return null;
      return await res.json();
    } catch (e) {
      return null;
    }
  }

  /**
   * The best snapshot available without a network call: the one a previous
   * visit saved, else the one committed in data/.
   * @returns {Promise<{data: Object, source: string, captured: string|null}|null>}
   */
  async function snapshot(name) {
    var saved = SNAP ? SNAP.read(name) : null;
    if (saved) return { data: saved.data, source: 'saved', captured: saved.captured };

    var bundled = await committed(name);
    if (bundled) {
      return { data: bundled, source: 'bundled', captured: bundled.captured || null };
    }
    return null;
  }

  /** Keep only the release fields this site reads, before persisting. */
  function trimRelease(r) {
    return {
      tag_name: r.tag_name,
      name: r.name,
      html_url: r.html_url,
      published_at: r.published_at,
      created_at: r.created_at,
      prerelease: !!r.prerelease,
      draft: !!r.draft,
      body: r.body,
      assets: (r.assets || []).map(function (a) {
        return {
          name: a.name,
          size: a.size,
          download_count: a.download_count || 0,
          browser_download_url: a.browser_download_url,
          digest: a.digest || null
        };
      })
    };
  }

  /* --------------------------------------------------------- formatters -- */
  function num(n) {
    if (typeof n !== 'number' || !isFinite(n)) return '—';
    /* Latin digits in both languages. Version tags, file sizes, SHA-256
       digests and asset names on this site are all Latin, and a Bengali
       numeral sitting beside "v6.0.2-beta" reads worse than keeping one
       numeral system per line. Dates and units below still localise. */
    return n.toLocaleString('en-US');
  }

  function bytes(n) {
    if (typeof n !== 'number' || !isFinite(n) || n <= 0) return '—';
    var mb = n / 1048576;
    if (mb >= 1) return mb.toFixed(1) + ' MB';
    return Math.round(n / 1024) + ' KB';
  }

  /* Formatters are created once per locale: building an Intl formatter is not
     free and the release grid formats a few dozen values per render. */
  var dateCache = {};
  function dateFormatter(style) {
    var i18n = window.AVRO_I18N;
    var tag = i18n ? i18n.dateLocale() : 'en-GB';
    var key = tag + '|' + style;
    if (!dateCache[key]) {
      dateCache[key] = new Intl.DateTimeFormat(tag, {
        day: 'numeric',
        month: style === 'short' ? 'short' : 'long',
        year: 'numeric'
      });
    }
    return dateCache[key];
  }

  function monthFormatter() {
    var i18n = window.AVRO_I18N;
    var tag = i18n ? i18n.dateLocale() : 'en-GB';
    var key = tag + '|monthonly';
    if (!dateCache[key]) {
      dateCache[key] = new Intl.DateTimeFormat(tag, { month: 'long', year: 'numeric' });
    }
    return dateCache[key];
  }

  function longDate(iso) {
    if (!iso) return '—';
    var d = new Date(iso);
    if (isNaN(d)) return '—';
    return dateFormatter('long').format(d);
  }

  function shortDate(iso) {
    if (!iso) return '—';
    var d = new Date(iso);
    if (isNaN(d)) return '—';
    return dateFormatter('short').format(d);
  }

  function monthYear(iso) {
    if (!iso) return T('changelog.unknownMonth');
    var d = new Date(iso);
    if (isNaN(d)) return T('changelog.unknownMonth');
    return monthFormatter().format(d);
  }

  var relCache = {};
  function relative(iso) {
    if (!iso) return '';
    var ms = Date.now() - new Date(iso).getTime();
    if (!isFinite(ms)) return '';

    var i18n = window.AVRO_I18N;
    var tag = i18n ? i18n.relativeLocale() : 'en';
    if (!relCache[tag]) relCache[tag] = new Intl.RelativeTimeFormat(tag, { numeric: 'auto' });
    var rtf = relCache[tag];

    var units = [['year', 31536000000], ['month', 2592000000], ['day', 86400000], ['hour', 3600000]];
    for (var i = 0; i < units.length; i++) {
      if (Math.abs(ms) >= units[i][1]) return rtf.format(-Math.round(ms / units[i][1]), units[i][0]);
    }
    return rtf.format(0, 'day');
  }

  function stripMarkdown(md) {
    if (!md) return '';
    return String(md)
      .replace(/```[\s\S]*?```/g, ' ')
      .replace(/!\[[^\]]*\]\([^)]*\)/g, ' ')
      .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
      .replace(/<[^>]+>/g, ' ')
      .replace(/^\s{0,3}[>#]+\s?/gm, '')
      .replace(/^\s*[-*+]\s+/gm, '')
      .replace(/[*_`~|]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  /** Summarise a release body when no curated summary exists for its tag. */
  function deriveSummary(md) {
    var text = stripMarkdown(md);
    if (!text) return '';
    /* Drop the boilerplate pre-release banner these releases open with. */
    if (text.charAt(0) === '\u26a0') {
      var cut = text.search(/[।.]\s/);
      if (cut > 0 && cut < 400) text = text.slice(cut + 1).trim();
    }
    if (text.length > 200) text = text.slice(0, 197).replace(/\s\S*$/, '') + '…';
    return text;
  }

  /* ------------------------------------------------------- link rewriting -- */
  /* Release notes still reference the retired Avro-Keyboard-Releases repo in
     both link targets and link labels (its support table links to that repo's
     issue tracker). Rewrite every occurrence so the site never publishes a
     dead link or a stale label. */
  var LEGACY = /Avro-Keyboard-Releases/g;
  /* The pattern matches the bare repository name because the retired name also
     appears as link text and inside owner-qualified URLs. The replacement must
     therefore be the bare name as well — substituting the full 'owner/repo'
     here would produce 'owner/owner/repo' inside every rewritten URL. */
  var LEGACY_FIX = 'Avro-Keyboard';

  function normalizeHtml(html) {
    return String(html).replace(LEGACY, LEGACY_FIX);
  }

  function normalizeText(text) {
    return String(text).replace(LEGACY, LEGACY_FIX);
  }

  /** Make off-site links open safely in a new tab. */
  function hardenLinks(root) {
    var links = root.querySelectorAll('a[href]');
    for (var i = 0; i < links.length; i++) {
      var a = links[i];
      var href = a.getAttribute('href') || '';
      if (/^https?:/i.test(href)) {
        try {
          if (new URL(href, location.href).host !== location.host) {
            a.setAttribute('target', '_blank');
            a.setAttribute('rel', 'noopener noreferrer');
          }
        } catch (e) { /* leave relative or malformed hrefs alone */ }
      }
    }
    return root;
  }

  /* ------------------------------------------------------------ releases -- */
  function normalizeRelease(r) {
    var assets = (r.assets || []).map(function (a) {
      return {
        name: a.name,
        size: a.size,
        downloads: a.download_count || 0,
        url: a.browser_download_url,
        digest: (a.digest || '').replace(/^sha256:/, '')
      };
    });
    return {
      tag: r.tag_name,
      name: normalizeText(r.name || r.tag_name),
      url: r.html_url,
      date: r.published_at || r.created_at,
      prerelease: !!r.prerelease,
      draft: !!r.draft,
      body: normalizeText(r.body || ''),
      assets: assets,
      downloads: assets.reduce(function (sum, a) { return sum + a.downloads; }, 0),
      summary: cfg.summaries[r.tag_name] || deriveSummary(r.body || '')
    };
  }

  function pickAsset(assets, kind, arch) {
    var want = arch === 'win32' ? 'win32' : 'win64';
    var i;
    for (i = 0; i < assets.length; i++) {
      var n = assets[i].name.toLowerCase();
      if (n.indexOf(want) !== -1 && n.indexOf(kind) !== -1) return assets[i];
    }
    for (i = 0; i < assets.length; i++) {
      if (assets[i].name.toLowerCase().indexOf(kind) !== -1) return assets[i];
    }
    return null;
  }

  function detectArch() {
    var ua = navigator.userAgent || '';
    if (/arm64|aarch64/i.test(ua)) return 'win-arm64';
    if (/Win64|x64|x86_64|amd64|WOW64/i.test(ua)) return 'win64';
    if (/Windows/i.test(ua)) return 'win32';
    return 'win64';
  }

  /* --------------------------------------------------------------- reads -- */
  async function commitCount() {
    var r = await get(U.commits);
    if (r.link) {
      var m = r.link.match(/[?&]page=(\d+)[^>]*>;\s*rel="last"/);
      if (m) return parseInt(m[1], 10);
    }
    return Array.isArray(r.data) ? r.data.length : null;
  }

  async function liveStats() {
    var out = {};
    var ok = 0;

    var jobs = [
      get(U.repo).then(function (r) {
        var d = r.data;
        out.stars = d.stargazers_count;
        out.forks = d.forks_count;
        out.issues = d.open_issues_count;
        out.watchers = d.subscribers_count;
        out.pushed = d.pushed_at;
        out.language = d.language;
        out.licence = (d.license || {}).spdx_id || null;
        out.created = d.created_at;
        ok++;
      }),
      commitCount().then(function (n) {
        if (typeof n === 'number') { out.commits = n; ok++; }
      }),
      get(U.contributors).then(function (r) {
        if (Array.isArray(r.data)) { out.contributors = r.data.length; ok++; }
      }),
      get(U.compare, { cache: false }).then(function (r) {
        if (typeof r.data.ahead_by === 'number') {
          out.ahead = r.data.ahead_by;
          out.behind = r.data.behind_by;
          ok++;
        }
      })
    ];

    await Promise.all(jobs.map(function (p) { return p.catch(function () { }); }));

    /* Every real response is folded into the saved snapshot so a later visit
       still gets these numbers when the API is unavailable. Only the fields
       that actually succeeded are offered, so a partial failure can never
       overwrite a value that a previous visit learned. */
    if (ok > 0 && SNAP) SNAP.write('repo', out);

    return { data: out, live: ok > 0, complete: ok === jobs.length };
  }

  async function snapshotStats() {
    var snap = await snapshot('repo');
    if (!snap) return null;
    var data = Object.assign({}, snap.data);
    delete data.captured;
    return { data: data, source: snap.source, captured: snap.captured };
  }

  async function releases() {
    try {
      var r = await get(U.releases);
      if (Array.isArray(r.data)) {
        if (SNAP) SNAP.write('releases', { releases: r.data.map(trimRelease) });
        return { data: r.data.map(normalizeRelease), live: true, source: 'live', captured: null };
      }
    } catch (e) { /* fall through to the snapshot */ }

    var snap = await snapshot('releases');
    var list = (snap && snap.data && snap.data.releases) ? snap.data.releases : null;
    if (list) {
      return {
        data: list.map(normalizeRelease),
        live: false,
        source: snap.source,
        captured: snap.captured
      };
    }
    return { data: [], live: false, source: 'none', captured: null };
  }

  async function official() {
    var base = {
      version: OFF.version,
      released: OFF.released,
      archived: true
    };
    try {
      var r = await get(U.official);
      var live = {
        archived: !!r.data.archived,
        stars: r.data.stargazers_count,
        forks: r.data.forks_count,
        issues: r.data.open_issues_count,
        pushed: r.data.pushed_at,
        licence: (r.data.license || {}).spdx_id || null
      };
      if (SNAP) SNAP.write('official', live);
      return { data: Object.assign({}, base, live), live: true, source: 'live', captured: null };
    } catch (e) { /* fall through */ }

    var snap = await snapshot('official');
    if (snap) {
      var copy = Object.assign({}, snap.data);
      delete copy.captured;
      return {
        data: Object.assign({}, base, copy),
        live: false,
        source: snap.source,
        captured: snap.captured
      };
    }
    return { data: base, live: false, source: 'none', captured: null };
  }

  async function commitsFor(tag) {
    try {
      var r = await get(U.commitsFor(tag));
      if (Array.isArray(r.data)) return { data: r.data, live: true };
    } catch (e) { /* fall through */ }
    return { data: [], live: false };
  }

  async function compareTags(from, to) {
    try {
      var r = await get(U.compareTags(from, to), { cache: false });
      if (r.data && Array.isArray(r.data.commits)) {
        return { data: r.data.commits, live: true };
      }
    } catch (e) { /* fall through */ }
    return { data: [], live: false };
  }

  return {
    BASE: BASE,
    urls: U,
    get: get,
    snapshot: snapshot,
    snapshotStats: function () { return once('snapshotStats', snapshotStats); },
    liveStats: function () { return once('liveStats', liveStats); },
    releases: function () { return once('releases', releases); },
    official: function () { return once('official', official); },
    commitsFor: function (tag) {
      return once('commitsFor:' + tag, function () { return commitsFor(tag); });
    },
    compareTags: function (from, to) {
      return once('compareTags:' + from + ':' + to, function () { return compareTags(from, to); });
    },
    detectArch: detectArch,
    pickAsset: pickAsset,
    normalizeHtml: normalizeHtml,
    normalizeText: normalizeText,
    hardenLinks: hardenLinks,
    deriveSummary: deriveSummary,
    stripMarkdown: stripMarkdown,
    fmt: {
      num: num,
      bytes: bytes,
      longDate: longDate,
      shortDate: shortDate,
      monthYear: monthYear,
      relative: relative
    }
  };
})();
