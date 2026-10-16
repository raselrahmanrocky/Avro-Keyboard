/* ==========================================================================
   Live counter strip.

   Paints the best available snapshot immediately so the page is never empty,
   then replaces those values with live GitHub numbers. Whatever happens, the
   status line says exactly which layer the visitor is looking at: a live
   response, the snapshot this browser saved on an earlier visit, or the
   snapshot bundled with the site.
   ========================================================================== */
(function () {
  'use strict';

  var GH = window.AVRO_GH;
  var I18N = window.AVRO_I18N;
  var tiles = Array.prototype.slice.call(document.querySelectorAll('.stat[data-stat]'));
  if (!tiles.length) return;

  var note = document.getElementById('statsStatus');
  var dots = Array.prototype.slice.call(document.querySelectorAll('[data-live-dot]'));
  var painted = {};

  /* The two passes, remembered so a language change can redraw the strip
     without asking GitHub for anything again. */
  var snapshotPass = null;
  var livePass = null;
  var message = { state: 'loading', key: 'status.loading', opts: null };

  function t(key, vars) {
    return I18N ? I18N.t(key, vars) : key;
  }

  /* Timestamps are stored as ISO, never as text: a relative time formatted in
     one language must not be reused after the visitor switches language. */
  function messageVars(opts) {
    if (!opts || opts.whenIso === undefined) return null;
    return {
      when: opts.whenIso ? GH.fmt.relative(opts.whenIso) : t('data.whenUnknown')
    };
  }

  function reduceMotion() {
    return window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  }

  /* The real number must never depend on the animation. requestAnimationFrame
     is throttled or never scheduled in background tabs and some embedded
     webviews, which would otherwise leave every counter showing a placeholder
     until the visitor happened to focus the tab. Two timers guarantee the
     final value lands either way. */
  function animate(el, to, instant) {
    var finalText = GH.fmt.num(to);

    if (instant || reduceMotion() || typeof to !== 'number' || !isFinite(to)) {
      el.textContent = finalText;
      return;
    }

    var duration = 780;
    var start = null;
    var settled = false;
    var rafStarted = false;

    function settle() {
      if (settled) return;
      settled = true;
      el.textContent = finalText;
    }

    function step(ts) {
      if (settled) return;
      rafStarted = true;
      if (start === null) start = ts;
      var p = Math.min((ts - start) / duration, 1);
      var eased = 1 - Math.pow(1 - p, 3);
      el.textContent = GH.fmt.num(Math.round(to * eased));
      if (p < 1) requestAnimationFrame(step);
      else settle();
    }

    requestAnimationFrame(step);

    /* No frame arrived at all: paint the number promptly instead of waiting
       out the animation window. */
    setTimeout(function () { if (!rafStarted) settle(); }, 150);
    /* Backstop so a stalled animation can still never leave a placeholder. */
    setTimeout(settle, duration + 200);
  }

  function paint(data, state, instant) {
    tiles.forEach(function (tile) {
      var key = tile.getAttribute('data-stat');
      if (!Object.prototype.hasOwnProperty.call(data, key)) return;

      var el = tile.querySelector('[data-value]');
      var value = data[key];
      if (!el) return;

      if (key === 'pushed') {
        el.textContent = value ? GH.fmt.relative(value) : '—';
        if (value) el.title = GH.fmt.longDate(value);
      } else if (typeof value === 'number') {
        if (instant) {
          el.textContent = GH.fmt.num(value);
          painted[key] = value;
        } else if (painted[key] !== value) {
          animate(el, value);
          painted[key] = value;
        }
      } else {
        el.textContent = '—';
      }

      tile.setAttribute('data-state', state);
      tile.setAttribute('data-source', state);
    });
  }

  function renderMessage() {
    if (!note) return;
    note.setAttribute('data-state', message.state);
    var text = note.querySelector('[data-note-text]');
    if (text) text.textContent = t(message.key, messageVars(message.opts));
    dots.forEach(function (dot) { dot.setAttribute('data-state', message.state); });
  }

  function say(state, key, opts) {
    message = { state: state, key: key, opts: opts || null };
    renderMessage();
  }

  /** Snapshot wording shared by the two fallback layers. */
  function snapshotMessage(source) {
    return source === 'saved' ? 'status.saved' : 'status.bundled';
  }

  function redraw() {
    if (snapshotPass) paint(snapshotPass.data, 'snapshot', true);
    if (livePass && livePass.live) paint(livePass.data, 'live', true);
    renderMessage();
  }

  (async function run() {
    say('loading', 'status.loading');

    var snapshot = await GH.snapshotStats();
    if (snapshot && snapshot.data) {
      snapshotPass = snapshot;
      paint(snapshot.data, 'snapshot', false);
    }

    var live = await GH.liveStats();

    if (live.live) {
      livePass = live;
      paint(live.data, 'live', false);
      say('live', live.complete ? 'status.live' : 'status.partial');
    } else if (snapshot && snapshot.data) {
      say('snapshot', snapshotMessage(snapshot.source), { whenIso: snapshot.captured });
    } else {
      say('error', 'status.error');
    }
  })();

  /* A language switch changes the labels, the relative date and the wording of
     the status line — all of which we already have in memory. */
  document.addEventListener('avro:locale', redraw);
})();
