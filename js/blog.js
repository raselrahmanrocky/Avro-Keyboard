/* ==========================================================================
   Blog page.

   Posts are plain markdown files committed under blog/ on the published
   branch. The index (blog/posts.json) and the post bodies are read from the
   raw GitHub CDN at runtime, so publishing a post never waits for a site
   deploy. Like the rest of this site, the page paints from the best source
   available: the live CDN first, then the snapshot a previous visit saved in
   this browser, then data/blog.json committed with the site. A post body
   that cannot be reached falls back to its cached copy, then to the
   same-origin copy committed with the site, and finally to its summary, so
   the page is never blank.

   One post is written in one language; every card carries a language badge
   and the list puts the active language first, each group newest first.
   ========================================================================== */
(function () {
  'use strict';

  var cfg = window.AVRO;
  var GH = window.AVRO_GH;
  var SNAP = window.AVRO_SNAP;
  var I18N = window.AVRO_I18N;
  var host = document.getElementById('blogHost');
  if (!host || !GH || !GH.fmt) return;

  var note = document.getElementById('blogStatus');
  var RAW = 'https://raw.githubusercontent.com/' + cfg.source.owner + '/' + cfg.source.repo +
    '/' + cfg.blog.branch + '/' + cfg.blog.dir + '/';
  var bodies = {};
  var firstBuild = true;

  function t(key, vars) {
    return I18N ? I18N.t(key, vars) : key;
  }

  function tn(n, key, vars) {
    return I18N ? I18N.tn(n, key, vars) : key;
  }

  function esc(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  var ICONS = { read: 'fa-book-open', back: 'fa-arrow-left', edit: 'fa-pen-to-square', date: 'fa-calendar-days' };

  function icon(id) {
    return '<i class="fa-solid ' + (ICONS[id] || 'fa-circle-info') + ' ic" aria-hidden="true"></i>';
  }

  function params() {
    try { return new URLSearchParams(location.search); } catch (e) { return new URLSearchParams(); }
  }

  function currentSlug() {
    var slug = params().get('post') || '';
    return /^[a-z0-9-]+$/i.test(slug) ? slug : '';
  }

  /* --------------------------------------------------------------- reads -- */
  async function fetchText(url) {
    try {
      var res = await fetch(url, { cache: 'no-cache' });
      if (!res.ok) return null;
      return await res.text();
    } catch (e) {
      return null;
    }
  }

  function store() {
    var entry = SNAP ? SNAP.read('blog') : null;
    return entry ? entry.data : null;
  }

  function remember(patch) {
    if (!SNAP) return;
    var current = store() || {};
    SNAP.write('blog', {
      index: patch.index !== undefined ? patch.index : current.index,
      bodies: patch.bodies !== undefined ? patch.bodies : current.bodies
    });
  }

  async function loadIndex() {
    var live = await fetchText(RAW + 'posts.json');
    if (live) {
      try {
        var data = JSON.parse(live);
        if (data && Array.isArray(data.posts)) {
          remember({ index: data });
          return { index: data, source: 'live', captured: null };
        }
      } catch (e) { /* malformed index: the snapshots below are the fallback */ }
    }

    var saved = store();
    if (saved && saved.index && Array.isArray(saved.index.posts)) {
      var info = SNAP.info('blog');
      return { index: saved.index, source: 'saved', captured: info ? info.captured : null };
    }

    /* The bundled copy is read directly rather than through GH.snapshot():
       that helper prefers the saved entry, which may hold post bodies but no
       index yet (bodies can be saved before a full index ever was). */
    var file = await fetchText('data/blog.json');
    if (file) {
      try {
        var bundled = JSON.parse(file);
        if (bundled && Array.isArray(bundled.posts)) {
          return { index: bundled, source: 'bundled', captured: bundled.generated || null };
        }
      } catch (e) { /* no index anywhere: the page shows the empty state */ }
    }
    return null;
  }

  async function loadBody(post) {
    var file = post.file || post.slug + '.md';
    var live = await fetchText(RAW + file);
    if (live !== null) {
      bodies[post.slug] = live;
      remember({ bodies: bodies });
      return live;
    }

    var saved = store();
    if (saved && saved.bodies && typeof saved.bodies[post.slug] === 'string') {
      bodies[post.slug] = saved.bodies[post.slug];
      return bodies[post.slug];
    }

    /* Same-origin copy: the .md file committed with the site. Covers a local
       preview before the post was ever pushed, and a deploy where the raw
       CDN is slow or unreachable. File names come from our own index, but a
       strict pattern keeps a tampered one out of the URL anyway. */
    if (/^[a-z0-9][a-z0-9._-]*$/i.test(file)) {
      var local = await fetchText(cfg.blog.dir + '/' + file);
      if (local !== null) {
        bodies[post.slug] = local;
        remember({ bodies: bodies });
        return local;
      }
    }
    return null;
  }

  /* --------------------------------------------------------------- pieces -- */
  /* Active language first, then newest first; drafts can never be listed
     even if an old index still carries one. */
  function sortedPosts(list) {
    var wanted = I18N ? I18N.locale() : 'en';
    return (list || []).filter(function (post) {
      return post && !post.draft && post.slug && post.title;
    }).slice().sort(function (a, b) {
      var am = a.lang === wanted ? 0 : 1;
      var bm = b.lang === wanted ? 0 : 1;
      if (am !== bm) return am - bm;
      return String(b.date || '').localeCompare(String(b.date || ''));
    });
  }

  function languageLabel(lang) {
    var labels = I18N && I18N.LABELS;
    if (labels && labels[lang] && labels[lang].native) return labels[lang].native;
    return String(lang || '').toUpperCase();
  }

  /* ------------------------------------------------------------- byline -- */
  /* The post's author: front-matter overrides win, otherwise the config's
     default author. The profile link only ever applies to the default
     author, so an override can never point at the wrong profile. */
  function authorOf(post) {
    var preset = cfg.author || {};
    var override = !!post.author;
    var name = override ? post.author : (I18N ? I18N.pick(preset.name) : '');
    return {
      name: name,
      role: override ? (post.authorRole || '') : (I18N ? I18N.pick(preset.role) : ''),
      avatar: post.authorAvatar || preset.avatar || '',
      url: override ? '' : (preset.url || ''),
      initials: initialsOf(name)
    };
  }

  function initialsOf(name) {
    var words = String(name || '').trim().split(/\s+/).filter(Boolean);
    var head = function (word) {
      if (window.Intl && window.Intl.Segmenter) {
        try {
          var parts = new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(word);
          var step = parts[Symbol.iterator]().next();
          if (!step.done) return step.value.segment;
        } catch (e) { /* plain first character below */ }
      }
      return String.fromCodePoint(word.codePointAt(0) || 32);
    };
    return words.slice(0, 2).map(head).join('').toUpperCase();
  }

  function avatarHtml(author, size) {
    var img = author.avatar
      ? '<img class="byline__img" src="' + esc(author.avatar) + '" alt="" loading="lazy" decoding="async">'
      : '';
    return '<span class="byline__avatar byline__avatar--' + size + (author.avatar ? '' : ' is-initials') + '" aria-hidden="true">' +
      img +
      '<span class="byline__initials"' + (author.avatar ? ' hidden' : '') + '>' + esc(author.initials) + '</span>' +
      '</span>';
  }

  function nameHtml(author) {
    if (!author.url) {
      return '<span class="byline__name">' + esc(author.name) + '</span>';
    }
    return '<a class="byline__name" href="' + esc(author.url) + '" target="_blank" rel="noopener noreferrer">' +
      esc(author.name) + '</a>';
  }

  function bylineSmall(post) {
    var author = authorOf(post);
    return '<div class="byline byline--sm">' +
      avatarHtml(author, 'sm') +
      nameHtml(author) +
      '<span class="byline__sep" aria-hidden="true">·</span>' +
      '<span class="byline__when">' + icon('date') +
      '<time datetime="' + esc(post.date || '') + '">' + esc(GH.fmt.longDate(post.date)) + '</time></span>' +
      '</div>';
  }

  function bylineLarge(post) {
    var author = authorOf(post);
    return '<div class="byline byline--lg">' +
      avatarHtml(author, 'lg') +
      '<div class="byline__text">' +
      nameHtml(author) +
      (author.role ? '<span class="byline__role">' + esc(author.role) + '</span>' : '') +
      '</div>' +
      '<p class="byline__meta">' +
      '<time datetime="' + esc(post.date || '') + '">' + esc(whenLine(post)) + '</time>' +
      (post.updated
        ? '<span class="byline__updated">' + esc(t('blog.updated', { date: GH.fmt.longDate(post.updated) })) + '</span>'
        : '') +
      '</p></div>';
  }

  /* A missing photo must never show a broken-image glyph: the initials
     fallback is revealed instead and the ring keeps its gradient. */
  function wireAvatars(root) {
    Array.prototype.forEach.call(root.querySelectorAll('img.byline__img'), function (img) {
      img.addEventListener('error', function () {
        img.hidden = true;
        var box = img.parentNode;
        if (!box) return;
        box.classList.add('is-initials');
        var initials = box.querySelector('.byline__initials');
        if (initials) initials.hidden = false;
      });
    });
  }

  function whenLine(post) {
    return t('blog.when', { date: GH.fmt.longDate(post.date) });
  }

  function tagMarks(post) {
    return (post.tags || []).map(function (tag) {
      return '<span class="mark">' + esc(tag) + '</span>';
    }).join('');
  }

  function langMark(post) {
    return '<span class="mark mark--lang">' + esc(languageLabel(post.lang)) + '</span>';
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

  /* --------------------------------------------------------------- views -- */
  function card(post) {
    var el = document.createElement('article');
    el.className = 'rel blog-card reveal';
    el.innerHTML =
      '<div class="rel-head"><div>' +
      '<h2><a href="?post=' + esc(post.slug) + '">' + esc(post.title) + '</a></h2>' +
      '</div><div class="marks">' + langMark(post) + tagMarks(post) + '</div></div>' +
      bylineSmall(post) +
      (post.excerpt ? '<p class="blog-excerpt">' + esc(post.excerpt) + '</p>' : '') +
      '<div class="rel-actions"><a class="btn btn-sm" href="?post=' + esc(post.slug) + '">' +
      icon('read') + esc(t('blog.readMore')) + '</a></div>';
    wireAvatars(el);
    return el;
  }

  function renderList(posts) {
    if (!posts.length) {
      host.innerHTML = '<p class="release-empty">' + esc(t('blog.empty')) + '</p>';
      return;
    }
    var list = document.createElement('div');
    list.className = 'blog-list';
    posts.forEach(function (post) { list.appendChild(card(post)); });
    host.appendChild(list);
  }

  function postBody(post, body) {
    if (body) return prose(body);
    var box = document.createElement('div');
    box.innerHTML = '<p class="note">' + esc(t('blog.loadFailed')) + '</p>' +
      (post.excerpt ? '<p class="blog-excerpt">' + esc(post.excerpt) + '</p>' : '');
    return box;
  }

  function renderPost(post, body) {
    var el = document.createElement('article');
    el.className = 'rel post reveal';

    var editUrl = 'https://github.com/' + cfg.source.owner + '/' + cfg.source.repo +
      '/edit/' + cfg.blog.branch + '/' + cfg.blog.dir + '/' + (post.file || post.slug + '.md');

    var current = I18N ? I18N.locale() : 'en';
    var lang = post.lang || 'en';

    el.innerHTML =
      '<div class="rel-head"><div>' +
      '<h2>' + esc(post.title) + '</h2>' +
      '</div><div class="marks">' + langMark(post) + tagMarks(post) + '</div></div>' +
      bylineLarge(post) +
      (lang !== current
        ? '<p class="note blog-lang-note">' + esc(t('blog.langNote', { lang: languageLabel(lang) })) + '</p>'
        : '');

    el.appendChild(postBody(post, body));
    wireAvatars(el);

    el.insertAdjacentHTML('beforeend',
      '<div class="rel-actions blog-post-foot">' +
      '<a class="btn btn-sm" href="blog.html">' + icon('back') + esc(t('blog.back')) + '</a>' +
      '<a class="btn btn-sm" href="' + esc(editUrl) + '" target="_blank" rel="noopener noreferrer">' +
      icon('edit') + esc(t('blog.edit')) + '</a>' +
      '</div>');
    return el;
  }

  function renderNotFound() {
    host.innerHTML = '<p class="release-empty">' + esc(t('blog.notFound')) + '</p>' +
      '<div class="rel-actions"><a class="btn btn-sm" href="blog.html">' +
      icon('back') + esc(t('blog.back')) + '</a></div>';
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

  /* --------------------------------------------------------------- build -- */
  async function build() {
    if (firstBuild) {
      say('loading', 'blog.status.loading');
      host.innerHTML = '<p class="release-empty">' + esc(t('blog.status.loading')) + '</p>';
    }

    var loaded = await loadIndex();
    var posts = loaded ? sortedPosts(loaded.index.posts) : [];
    var slug = currentSlug();
    var post = null;
    for (var i = 0; i < posts.length; i++) {
      if (posts[i].slug === slug) { post = posts[i]; break; }
    }

    host.innerHTML = '';

    if (slug) {
      if (!post) {
        renderNotFound();
      } else {
        var body = bodies[post.slug];
        if (body === undefined) body = await loadBody(post);
        host.appendChild(renderPost(post, body));
        document.title = post.title + ' — Avro Keyboard Community Edition';
      }
    } else {
      renderList(posts);
    }

    if (window.AVRO_MOTION) { window.AVRO_MOTION.scan(host); }

    if (!loaded) {
      say('error', 'blog.status.error');
    } else if (loaded.source === 'live') {
      say('live', 'blog.status.live', { n: posts.length });
    } else {
      say('snapshot', loaded.source === 'saved' ? 'blog.status.saved' : 'blog.status.bundled',
        { whenIso: loaded.captured });
    }

    firstBuild = false;
  }

  /* Builds are serialised: a language change during an in-flight build waits
     its turn instead of interleaving two DOM writes. */
  var queue = Promise.resolve();
  function schedule() {
    queue = queue.then(build)['catch'](function (error) {
      host.innerHTML = '<p class="release-empty">' + esc(t('blog.empty')) + '</p>';
      say('error', 'blog.status.error');
      if (window.console && console.error) console.error('[blog]', error);
    });
    return queue;
  }

  schedule();
  document.addEventListener('avro:locale', schedule);
})();
