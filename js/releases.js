/* ==========================================================================
   Release card grid.

   Cards come from this repository's own GitHub releases (newest first). Each
   release produces an installer card and, when portable assets exist, a
   portable card. If that leaves the grid short of three cards the remaining
   slots are filled with the official 5.6.0 baseline so the layout always
   reads as a complete archive. Future releases slot in automatically.

   Every render rebuilds the cards from the raw releases rather than reusing
   finished markup: the labels, ribbons and "released" dates are all
   translated, so a language change has to re-derive them from their source.
   The raw data comes from js/github.js's memo, so this costs no request.
   ========================================================================== */
(function () {
  'use strict';

  var cfg = window.AVRO;
  var GH = window.AVRO_GH;
  var I18N = window.AVRO_I18N;
  var grid = document.getElementById('releaseGrid');
  if (!grid) return;

  var note = document.getElementById('releasesStatus');
  var chips = Array.prototype.slice.call(document.querySelectorAll('[data-filter]'));
  var arch = GH.detectArch();
  var archLabel = { win32: '32-bit', win64: '64-bit', 'win-arm64': 'ARM64' }[arch] || '64-bit';

  /* The last successful read, kept so a language change re-renders without
     another API request. */
  var state = null;

  function t(key, vars) {
    return I18N ? I18N.t(key, vars) : key;
  }

  function tn(n, key, vars) {
    return I18N ? I18N.tn(n, key, vars) : key;
  }

  function pick(value) {
    return I18N ? I18N.pick(value) : (typeof value === 'string' ? value : '');
  }

  function esc(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function icon(id) {
    return '<svg class="ic" aria-hidden="true" focusable="false"><use href="#i-' + id + '"></use></svg>';
  }

  function specRow(label, value) {
    return '<div><dt>' + esc(label) + '</dt><dd>' + esc(value) + '</dd></div>';
  }

  /* ------------------------------------------------------------- cards -- */
  function cardHTML(card) {
    var ribbon = '<span class="ribbon' + (card.ribbon.cls ? ' ' + card.ribbon.cls : '') + '">' +
      esc(card.ribbon.text) + '</span>';

    var primary = '';
    if (card.primary) {
      primary = '<a class="btn btn-primary" href="' + esc(card.primary.href) + '"' +
        (card.primary.external ? ' target="_blank" rel="noopener noreferrer"' : '') + '>' +
        icon('download') + esc(card.primary.label) +
        (card.primary.external ? ' <span aria-hidden="true">↗</span>' : '') + '</a>';
    } else {
      primary = '<span class="btn" aria-disabled="true">' + esc(t('releases.noFile')) + '</span>';
    }

    return '<article class="release-card reveal' + (card.kind === 'official' ? ' release-card--official' : '') + '"' +
      ' data-kind="' + esc(card.kind) + '" data-tag="' + esc(card.tag || '') + '">' +
      ribbon +
      '<div class="rc-head">' +
      '<span class="rc-icon">' + icon(card.icon) + '</span>' +
      '<div><h3>' + esc(card.title) + '</h3><p class="when">' + esc(card.when) + '</p></div>' +
      '</div>' +
      '<p>' + esc(card.summary) + '</p>' +
      '<dl class="spec">' + card.spec.map(function (row) { return specRow(row[0], row[1]); }).join('') + '</dl>' +
      '<div class="rc-actions">' + primary +
      '<a class="btn-icon" href="' + esc(card.info) + '" aria-label="' +
      esc(t('releases.details', { title: card.title })) + '" title="Changelog">' +
      icon('info') + '</a>' +
      '</div>' +
      '</article>';
  }

  function fromRelease(release) {
    var cards = [];
    var setup = GH.pickAsset(release.assets, 'setup', arch);
    var portable = GH.pickAsset(release.assets, 'portable', arch);
    var when = t('releases.when', { date: GH.fmt.longDate(release.date) });
    var summary = pick(release.summary);
    var portableTitle = release.name + ' — ' + t('releases.portable');

    cards.push({
      kind: 'installer',
      tag: release.tag,
      ribbon: release.prerelease
        ? { text: t('releases.ribbon.prerelease'), cls: 'ribbon--pre' }
        : { text: t('releases.ribbon.stable'), cls: 'ribbon--live' },
      icon: 'keyboard',
      title: release.name,
      when: when,
      summary: summary,
      spec: [
        [t('releases.spec.size'), setup ? GH.fmt.bytes(setup.size) : '—'],
        [t('releases.spec.downloads'), setup ? GH.fmt.num(setup.downloads) : '—'],
        [t('releases.spec.arch'), archLabel],
        [t('releases.spec.licence'), 'MPL-2.0']
      ],
      primary: setup ? { label: t('releases.downloadExe', { arch: archLabel }), href: setup.url } : null,
      info: 'changelog.html#' + encodeURIComponent(release.tag)
    });

    if (portable) {
      cards.push({
        kind: 'portable',
        tag: release.tag,
        ribbon: { text: t('releases.ribbon.portable'), cls: 'ribbon--portable' },
        icon: 'package',
        title: portableTitle,
        when: when,
        summary: summary,
        spec: [
          [t('releases.spec.size'), GH.fmt.bytes(portable.size)],
          [t('releases.spec.downloads'), GH.fmt.num(portable.downloads)],
          [t('releases.spec.arch'), archLabel],
          [t('releases.spec.licence'), 'MPL-2.0']
        ],
        primary: { label: t('releases.downloadZip', { arch: archLabel }), href: portable.url },
        info: 'changelog.html#' + encodeURIComponent(release.tag)
      });
    }

    return cards;
  }

  function officialCard(variant) {
    var portable = variant === 'portable';
    return {
      kind: 'official',
      tag: cfg.officialArchive.tag,
      ribbon: {
        text: portable ? t('releases.ribbon.officialPortable') : t('releases.ribbon.official'),
        cls: ''
      },
      icon: portable ? 'package' : 'archive',
      title: 'Avro Keyboard ' + cfg.official.version + (portable ? ' — ' + t('releases.portable') : ''),
      when: t('releases.when', { date: GH.fmt.longDate(cfg.official.released) }),
      summary: t(portable ? 'releases.officialPortable.summary' : 'releases.official.summary'),
      spec: [
        [t('releases.spec.version'), cfg.official.version],
        [t('releases.spec.released'), GH.fmt.longDate(cfg.official.released)],
        [t('releases.spec.platform'), pick(cfg.official.platform)],
        [t('releases.spec.sourceLicence'), pick(cfg.official.licence)]
      ],
      primary: {
        label: t('releases.official.cta'),
        href: portable ? cfg.official.portableUrl : cfg.official.installerUrl,
        external: true
      },
      info: 'changelog.html#' + cfg.officialArchive.tag
    };
  }

  function buildCards(releases) {
    var cards = [];
    releases.slice(0, cfg.maxReleases).forEach(function (release) {
      cards = cards.concat(fromRelease(release));
    });

    /* Fill the grid with the official baseline when few releases exist yet. */
    var variants = ['installer', 'portable'];
    for (var i = 0; cards.length < cfg.minCards && i < variants.length; i++) {
      cards.push(officialCard(variants[i]));
    }
    return cards;
  }

  /* ------------------------------------------------------------ filters -- */
  function currentFilter() {
    var active = chips.filter(function (c) { return c.getAttribute('aria-pressed') === 'true'; })[0];
    return active ? active.getAttribute('data-filter') : 'all';
  }

  function applyFilter(kind) {
    var visible = 0;
    Array.prototype.forEach.call(grid.querySelectorAll('.release-card'), function (card) {
      var show = kind === 'all' || card.getAttribute('data-kind') === kind;
      card.hidden = !show;
      if (show) visible++;
    });
    var empty = grid.querySelector('.release-empty');
    if (empty) empty.hidden = visible !== 0;
  }

  /* `opts.n` picks the English singular form (see AVRO_I18N.tn); `opts.whenIso`
     keeps the timestamp as data so the relative phrase is rebuilt in the
     active language every time the line is drawn. */
  function say(stateName, key, opts) {
    if (!note) return;
    note.setAttribute('data-state', stateName);
    var text = note.querySelector('[data-note-text]');
    if (!text) return;

    opts = opts || {};
    var vars = {};
    if (opts.whenIso !== undefined) {
      vars.when = opts.whenIso ? GH.fmt.relative(opts.whenIso) : t('data.whenUnknown');
    }
    if (opts.n !== undefined && opts.n !== null) vars.n = opts.n;

    var empty = Object.keys(vars).length === 0;
    text.textContent = (opts.n === undefined || opts.n === null)
      ? t(key, empty ? null : vars)
      : tn(opts.n, key, empty ? null : vars);
  }

  /* Snapshot wording is shared with the counter strip: `saved` means this
     browser kept real data from an earlier visit, `bundled` means the copy
     that ships with the site. */
  function snapshotKey(source) {
    return source === 'saved' ? 'releases.status.saved' : 'releases.status.bundled';
  }

  /* ------------------------------------------------------------- render -- */
  function paint() {
    if (!state) return;

    var releases = state.releases;
    var result = state.result;
    var cards = buildCards(releases);

    if (!cards.length) {
      grid.innerHTML = '<p class="release-empty">' + esc(t('releases.empty.none')) + '</p>';
      say('error', 'releases.status.error');
      return;
    }

    grid.innerHTML = cards.map(cardHTML).join('') +
      '<p class="release-empty" hidden>' + esc(t('releases.empty.filtered')) + '</p>';

    if (window.AVRO_MOTION) { window.AVRO_MOTION.scan(grid); }

    /* The chips ship disabled in the HTML so nothing is clickable before the
       data lands; they become usable the moment there are cards to filter. */
    chips.forEach(function (chip) { chip.disabled = false; });
    applyFilter(currentFilter());

    if (result.live) {
      say('live', 'releases.status.live', { n: releases.length });
    } else if (result.source === 'none') {
      say('error', 'releases.status.error');
    } else {
      var ours = cards.filter(function (c) { return c.kind !== 'official'; }).length;
      say('snapshot', snapshotKey(result.source), { n: ours, whenIso: result.captured });
    }
  }

  /* Chips are wired once: a language change redraws the grid but the filter
     buttons themselves stay put, so re-binding would double-fire listeners. */
  chips.forEach(function (chip) {
    chip.addEventListener('click', function () {
      chips.forEach(function (other) { other.setAttribute('aria-pressed', 'false'); });
      chip.setAttribute('aria-pressed', 'true');
      applyFilter(chip.getAttribute('data-filter'));
    });
  });

  (async function run() {
    say('loading', 'releases.status.loading');
    chips.forEach(function (chip) { chip.disabled = true; });

    var result = await GH.releases();
    state = {
      result: result,
      releases: (result.data || []).filter(function (r) { return !r.draft; })
    };
    paint();
  })();

  document.addEventListener('avro:locale', paint);
})();
