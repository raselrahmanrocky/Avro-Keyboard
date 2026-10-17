/* ==========================================================================
   Audit cards: official Avro Keyboard vs this Community Edition.

   Every figure here is fetched live (with the saved snapshot first and the
   bundled snapshot second as fallbacks). Nothing is hardcoded except the
   officially published facts — the last official version, its release date,
   and the platform list from OmicronLab.com.
   ========================================================================== */
(function () {
  'use strict';

  var cfg = window.AVRO;
  var GH = window.AVRO_GH;
  var I18N = window.AVRO_I18N;

  var officialCard = document.getElementById('auditOfficial');
  var ourCard = document.getElementById('auditCe');
  if (!officialCard && !ourCard) return;

  function t(key, vars) {
    return I18N ? I18N.t(key, vars) : key;
  }

  function pick(value) {
    return I18N ? I18N.pick(value) : (typeof value === 'string' ? value : '');
  }

  /* Values learned so far, so a language change can redraw the cards without
     another API round trip. */
  var officialData = null;
  var ourData = null;
  var latest = null;

  function fill(root, values) {
    if (!root) return;
    var touched = false;
    Object.keys(values).forEach(function (key) {
      var el = root.querySelector('[data-audit="' + key + '"]');
      if (!el) return;
      var value = values[key];
      if (value === null || value === undefined || value === '') return;
      el.textContent = value;
      touched = true;
    });
    if (touched) root.setAttribute('data-state', 'live');
  }

  function fmtDate(iso) {
    return iso ? GH.fmt.longDate(iso) : null;
  }

  function officialValues(o) {
    return {
      released: fmtDate(o.released || cfg.official.released),
      stars: typeof o.stars === 'number' ? GH.fmt.num(o.stars) : undefined,
      forks: typeof o.forks === 'number' ? GH.fmt.num(o.forks) : undefined,
      issues: typeof o.issues === 'number' ? GH.fmt.num(o.issues) : undefined,
      archived: o.archived ? t('audit.archived') : t('audit.active'),
      pushed: fmtDate(o.pushed),
      licence: o.licence || pick(cfg.official.licence)
    };
  }

  function ourValues(s) {
    return {
      commits: typeof s.commits === 'number' ? GH.fmt.num(s.commits) : undefined,
      stars: typeof s.stars === 'number' ? GH.fmt.num(s.stars) : undefined,
      forks: typeof s.forks === 'number' ? GH.fmt.num(s.forks) : undefined,
      ahead: typeof s.ahead === 'number' ? GH.fmt.num(s.ahead) : undefined,
      contributors: typeof s.contributors === 'number' ? GH.fmt.num(s.contributors) : undefined,
      licence: s.licence || 'MPL-2.0',
      language: s.language || 'Pascal'
    };
  }

  /** Freshness line shared by both cards. */
  function freshness(root, iso) {
    if (!root || !iso) return;
    var el = root.querySelector('[data-audit="freshness"]');
    if (el) el.textContent = t('audit.freshness', { when: GH.fmt.relative(iso) });
  }

  function render() {
    if (officialData) {
      fill(officialCard, officialValues(officialData));
      freshness(officialCard, officialData.pushed);
    }
    if (ourData) {
      fill(ourCard, ourValues(ourData));
      freshness(ourCard, ourData.pushed);
    }
    if (latest) {
      fill(ourCard, { latest: latest.tag, when: fmtDate(latest.date) });
    }
  }

  (async function run() {
    /* ---- pass 1: snapshot (saved first, then bundled) -------------------- */
    var statsSnap = await GH.snapshotStats();
    var officialSnap = await GH.snapshot('official');
    var snaps = await GH.releases();

    if (officialSnap && officialSnap.data) {
      officialData = officialSnap.data;
    }
    if (statsSnap && statsSnap.data) {
      ourData = statsSnap.data;
    }
    if (snaps.data && snaps.data.length) {
      latest = snaps.data[0];
    }
    render();

    /* ---- pass 2: live ---------------------------------------------------- */
    var liveStats = await GH.liveStats();
    var liveOfficial = await GH.official();

    if (liveOfficial.live) officialData = liveOfficial.data;
    if (liveStats.live) {
      ourData = Object.assign({}, ourData, liveStats.data);
    }
    render();

    /* The "ahead" figure also appears in the footer and in a note; those
       markers are filled by js/ahead-note.js, which every page loads. */
  })();

  document.addEventListener('avro:locale', render);
})();
