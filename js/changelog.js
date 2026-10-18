/* ==========================================================================
   Changelog page.

   Every release of this repository, newest first, with its notes rendered
   from the release body. A release whose body is empty gets its notes built
   from the commits it contains instead. The last official 5.6.0 release is
   appended as an archival entry so the page reads as a complete history.

   The page can be rebuilt in place: switching language re-runs the same
   build against data that js/github.js has already memoised, so no request
   and no byte of the visitor's hourly API allowance is spent again.
   ========================================================================== */
(function () {
  'use strict';

  var cfg = window.AVRO;
  var GH = window.AVRO_GH;
  var I18N = window.AVRO_I18N;
  var host = document.getElementById('changelog');
  if (!host) return;

  var nav = document.getElementById('tagNav');
  var note = document.getElementById('clStatus');
  var sections = [];
  var observer = null;
  var firstBuild = true;

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

  var ICONS = { download: 'fa-download', package: 'fa-box', external: 'fa-arrow-up-right-from-square' };

  function icon(id) {
    return '<i class="fa-solid ' + (ICONS[id] || 'fa-circle-info') + ' ic" aria-hidden="true"></i>';
  }

  /* ------------------------------------------------------------ markdown -- */
  function renderMarkdown(md) {
    var html;
    if (window.marked && typeof window.marked.parse === 'function') {
      html = window.marked.parse(md, { gfm: true, breaks: false });
    } else {
      /* Never leave the page blank if the renderer is unavailable. */
      html = md.split(/\n{2,}/).map(function (block) {
        return '<p>' + esc(block).replace(/\n/g, '<br>') + '</p>';
      }).join('');
    }

    /* Retired-repo links are rewritten before sanitising so no dead link can
       survive into the DOM. */
    html = GH.normalizeHtml(html);

    if (window.DOMPurify) {
      html = window.DOMPurify.sanitize(html, {
        USE_PROFILES: { html: true },
        ADD_ATTR: ['target', 'rel']
      });
    }
    return html;
  }

  function prose(md) {
    var box = document.createElement('div');
    box.className = 'prose';
    box.innerHTML = renderMarkdown(md);

    Array.prototype.forEach.call(box.querySelectorAll('table'), function (table) {
      var wrap = document.createElement('div');
      wrap.className = 'prose-table';
      table.parentNode.insertBefore(wrap, table);
      wrap.appendChild(table);
    });

    return GH.hardenLinks(box);
  }

  /* -------------------------------------------------------------- pieces -- */
  function marksFor(release, derived) {
    var marks = [];
    if (release.prerelease) {
      marks.push('<span class="mark mark--pre">' + esc(t('changelog.mark.prerelease')) + '</span>');
    } else {
      marks.push('<span class="mark mark--live">' + esc(t('changelog.mark.stable')) + '</span>');
    }
    if (derived) {
      marks.push('<span class="mark mark--auto">' + esc(t('changelog.mark.auto')) + '</span>');
    }
    marks.push('<span class="mark">' + esc(release.tag) + '</span>');
    return marks.join('');
  }

  function headHTML(title, when, marks) {
    return '<div class="rel-head">' +
      '<div><h2>' + esc(title) + '</h2>' +
      '<p class="when">' + esc(when) + '</p></div>' +
      '<div class="marks">' + marks + '</div>' +
      '</div>';
  }

  function archLabel() {
    return { win32: '32-bit', win64: '64-bit', 'win-arm64': 'ARM64' }[GH.detectArch()] || '64-bit';
  }

  function actionsHTML(release) {
    var arch = archLabel();
    var setup = GH.pickAsset(release.assets, 'setup', GH.detectArch());
    var portable = GH.pickAsset(release.assets, 'portable', GH.detectArch());
    var out = '<div class="rel-actions">';

    if (setup) {
      out += '<a class="btn btn-primary" href="' + esc(setup.url) + '">' + icon('download') +
        esc(t('releases.downloadExe', { arch: arch })) + '</a>';
    }
    if (portable) {
      out += '<a class="btn btn-sm" href="' + esc(portable.url) + '">' + icon('package') +
        esc(t('releases.downloadZip', { arch: arch })) + '</a>';
    }
    out += '<a class="btn btn-sm" href="' + esc(release.url) + '" target="_blank" rel="noopener noreferrer">' +
      icon('external') + esc(t('changelog.viewOnGithub')) + '</a>';
    return out + '</div>';
  }

  function assetsHTML(release) {
    if (!release.assets.length) return '';
    var rows = release.assets.map(function (asset) {
      return '<li><div><span class="asset-name">' + esc(asset.name) + '</span>' +
        (asset.digest ? '<span class="asset-hash">sha256 ' + esc(asset.digest) + '</span>' : '') +
        '</div>' +
        '<span class="asset-meta">' + esc(GH.fmt.bytes(asset.size)) + ' · ' +
        esc(tn(asset.downloads, 'changelog.assets.downloads', { n: GH.fmt.num(asset.downloads) })) +
        '</span></li>';
    }).join('');

    return '<details class="assets"><summary>' +
      esc(tn(release.assets.length, 'changelog.assets.summary', { n: release.assets.length })) +
      '</summary>' +
      '<ul class="asset-list">' + rows + '</ul></details>';
  }

  /* ------------------------------------------------------------ sections -- */
  function releaseSection(release) {
    var el = document.createElement('article');
    el.className = 'rel reveal';
    el.id = release.tag;

    var hasBody = !!(release.body && release.body.trim());
    var title = release.name || release.tag;

    el.innerHTML = headHTML(title, t('changelog.when', { date: GH.fmt.longDate(release.date) }),
      marksFor(release, !hasBody)) + actionsHTML(release);

    if (hasBody) {
      el.appendChild(prose(release.body));
    } else {
      el.appendChild(autoNotes(release));
    }

    el.insertAdjacentHTML('beforeend', assetsHTML(release));
    return el;
  }

  /** Notes for a release that has no body: build them from its commits. */
  function autoNotes() {
    var box = document.createElement('div');
    box.className = 'notes-auto';
    box.innerHTML = '<p class="note">' + esc(t('changelog.autonotes.lead')) + '</p>' +
      '<ul class="commit-notes"><li><span class="skeleton" style="display:inline-block;width:200px">…</span></li></ul>';
    return box;
  }

  function fillAutoNotes(box, commits, truncated) {
    var list = box.querySelector('.commit-notes');
    if (!list) return;
    if (!commits.length) {
      list.innerHTML = '<li>' + esc(t('changelog.autonotes.unavailable')) + '</li>';
      return;
    }
    list.innerHTML = commits.map(function (c) {
      var msg = (c.commit && c.commit.message ? c.commit.message : '').split('\n')[0];
      return '<li><code>' + esc(String(c.sha).slice(0, 7)) + '</code><span>' + esc(msg) + '</span></li>';
    }).join('');
    if (truncated) {
      list.insertAdjacentHTML('afterend',
        '<p class="note">' + esc(t('changelog.autonotes.truncated')) + '</p>');
    }
  }

  function historySection(release, commits) {
    if (!commits.length) return null;

    var groups = {};
    var order = [];
    commits.forEach(function (c) {
      var meta = c.commit && (c.commit.committer || c.commit.author);
      var iso = (meta && meta.date) || '';
      var key = iso ? GH.fmt.monthYear(iso) : t('changelog.unknownMonth');
      if (!groups[key]) { groups[key] = []; order.push(key); }
      groups[key].push(c);
    });

    var el = document.createElement('article');
    el.className = 'rel reveal';
    el.id = 'history';
    el.innerHTML = headHTML(
      t('changelog.history.title', { tag: release.tag }),
      t('changelog.history.when', { n: GH.fmt.num(commits.length) }),
      '<span class="mark mark--auto">' + esc(t('changelog.mark.autoShort')) + '</span>'
    ) +
      '<div class="timeline">' + order.map(function (key) {
        return '<div class="tl-item"><time>' + esc(key) + '</time><ul class="commit-notes">' +
          groups[key].map(function (c) {
            var msg = (c.commit && c.commit.message ? c.commit.message : '').split('\n')[0];
            return '<li><code>' + esc(String(c.sha).slice(0, 7)) + '</code><span>' + esc(msg) + '</span></li>';
          }).join('') +
          '</ul></div>';
      }).join('') + '</div>';
    return el;
  }

  function officialSection() {
    var el = document.createElement('article');
    el.className = 'rel rel--official reveal';
    el.id = cfg.officialArchive.tag;

    var spec = [
      [t('releases.spec.version'), cfg.official.version],
      [t('releases.spec.released'), GH.fmt.longDate(cfg.official.released)],
      [t('releases.spec.platform'), pick(cfg.official.platform)],
      [t('releases.spec.sourceLicence'), pick(cfg.official.licence)],
      [t('releases.spec.status'), t('changelog.official.status')]
    ].map(function (row) {
      return '<div><dt>' + esc(row[0]) + '</dt><dd>' + esc(row[1]) + '</dd></div>';
    }).join('');

    el.innerHTML =
      headHTML('Avro Keyboard ' + cfg.official.version,
        t('changelog.official.when', { date: GH.fmt.longDate(cfg.official.released) }),
        '<span class="mark mark--archived">' + esc(t('changelog.mark.archived')) + '</span><span class="mark">' +
        esc(t('changelog.mark.official')) + '</span>') +
      '<div class="prose"><p>' + esc(pick(cfg.officialArchive.note)) + '</p></div>' +
      '<dl class="spec">' + spec + '</dl>' +
      '<div class="rel-actions">' +
      '<a class="btn" href="' + esc(cfg.official.installerUrl) + '" target="_blank" rel="noopener noreferrer">' +
      icon('external') + esc(t('changelog.official.download')) + '</a>' +
      '<a class="btn btn-sm" href="https://github.com/' + esc(cfg.official.owner) + '/' + esc(cfg.official.repo) +
      '" target="_blank" rel="noopener noreferrer">' + icon('external') + esc(t('changelog.official.source')) + '</a>' +
      '</div>';
    return el;
  }

  /* ----------------------------------------------------------------- nav -- */
  function buildNav(entries) {
    if (!nav) return;
    nav.innerHTML = '<h2>' + esc(t('changelog.nav.heading')) + '</h2><ol>' + entries.map(function (entry) {
      return '<li><a href="#' + esc(entry.id) + '" data-for="' + esc(entry.id) + '">' +
        esc(entry.label) + '<span class="nav-when">' + esc(entry.when) + '</span></a></li>';
    }).join('') + '</ol>';

    Array.prototype.forEach.call(nav.querySelectorAll('a'), function (a) {
      a.addEventListener('click', function () {
        setActive(a.getAttribute('data-for'));
      });
    });
  }

  function setActive(id) {
    if (!nav) return;
    Array.prototype.forEach.call(nav.querySelectorAll('a'), function (a) {
      a.setAttribute('aria-current', a.getAttribute('data-for') === id ? 'true' : 'false');
    });
  }

  function watchSections() {
    if (observer) observer.disconnect();
    if (!('IntersectionObserver' in window)) return;
    observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) setActive(entry.target.id);
      });
    }, { rootMargin: '-20% 0px -70% 0px' });
    sections.forEach(function (el) { observer.observe(el); });
  }

  function params() {
    try { return new URLSearchParams(location.search); } catch (e) { return new URLSearchParams(); }
  }

  function deepLink() {
    var wanted = (params().get('tag') || '').replace(/^#/, '');
    var hash = wanted ? '#' + wanted : location.hash;
    if (!hash || hash === '#') return;
    var target = document.getElementById(hash.slice(1));
    if (!target) return;
    setActive(target.id);
    target.scrollIntoView({ block: 'start', behavior: 'auto' });
  }

  /* Timestamps stay as data (`whenIso`) so the relative phrase is rebuilt in
     the active language rather than reused from the previous one. */
  function say(state, key, opts) {
    if (!note) return;
    note.setAttribute('data-state', state);
    var dot = note.querySelector('.dot');
    if (dot) dot.setAttribute('data-state', state);
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

  /* ----------------------------------------------------------------- build -- */
  async function build() {
    sections = [];
    if (nav) nav.innerHTML = '';
    if (observer) { observer.disconnect(); observer = null; }

    if (firstBuild) {
      say('loading', 'changelog.status.loading');
      host.innerHTML = '<p class="release-empty">' + esc(t('changelog.status.loading')) + '</p>';
    }

    var result = await GH.releases();
    var releases = (result.data || []).filter(function (r) { return !r.draft; });

    host.innerHTML = '';

    if (!releases.length) {
      host.innerHTML = '<p class="release-empty">' + esc(t('changelog.empty')) + '</p>';
      say('error', 'changelog.status.error');
      firstBuild = false;
      return;
    }

    var navEntries = [];
    var autoNoteHosts = [];

    releases.forEach(function (release) {
      var section = releaseSection(release);
      host.appendChild(section);
      sections.push(section);
      navEntries.push({
        id: release.tag,
        label: release.name || release.tag,
        when: GH.fmt.shortDate(release.date)
      });
      if (!release.body || !release.body.trim()) {
        var box = section.querySelector('.notes-auto');
        if (box) autoNoteHosts.push({ release: release, box: box });
      }
    });

    /* Commits behind the newest release, so the page carries real history. */
    var newest = releases[0];
    var commitsResult = await GH.commitsFor(newest.tag);
    var history = historySection(newest, commitsResult.data || []);
    if (history) {
      host.appendChild(history);
      sections.push(history);
      navEntries.push({
        id: 'history',
        label: t('changelog.history.nav'),
        when: tn(commitsResult.data.length, 'changelog.nav.commits', { n: GH.fmt.num(commitsResult.data.length) })
      });
    }

    var archive = officialSection();
    host.appendChild(archive);
    sections.push(archive);
    navEntries.push({
      id: cfg.officialArchive.tag,
      label: t('changelog.nav.official', { version: cfg.official.version }),
      when: '2019'
    });

    /* Fill in commit-derived notes for any release that lacked them. */
    for (var i = 0; i < autoNoteHosts.length; i++) {
      var item = autoNoteHosts[i];
      var previous = releases[releases.indexOf(item.release) + 1];
      var commits = [];
      if (previous) {
        var compared = await GH.compareTags(previous.tag, item.release.tag);
        commits = compared.data || [];
      } else {
        var upTo = await GH.commitsFor(item.release.tag);
        commits = upTo.data || [];
      }
      fillAutoNotes(item.box, commits, commits.length >= 100);
    }

    buildNav(navEntries);
    watchSections();

    if (window.AVRO_MOTION) { window.AVRO_MOTION.scan(host); }

    /* Only the first build may move the viewport to a deep link. */
    if (firstBuild) deepLink();

    if (result.live) {
      say('live', 'changelog.status.live', { n: releases.length });
    } else if (result.source === 'none') {
      say('error', 'changelog.status.error');
    } else {
      say('snapshot', result.source === 'saved' ? 'changelog.status.saved' : 'changelog.status.bundled',
        { whenIso: result.captured });
    }

    firstBuild = false;
  }

  /* Builds are serialised: a language change during an in-flight build waits
     its turn instead of interleaving two DOM writes. */
  var queue = Promise.resolve();
  function schedule() {
    queue = queue.then(build)['catch'](function (error) {
      host.innerHTML = '<p class="release-empty">' + esc(t('changelog.empty')) + '</p>';
      say('error', 'changelog.status.error');
      if (window.console && console.error) console.error('[changelog]', error);
    });
    return queue;
  }

  schedule();
  document.addEventListener('avro:locale', schedule);
})();
