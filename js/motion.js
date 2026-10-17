/* ==========================================================================
   Motion layer: scroll progress, reveal-on-scroll, the looping hero h1
   typewriter, hero particles, the marquee clone, magnetic buttons, card
   tilt and the floating back-to-top control.

   Every effect here is decorative and opt-out friendly: reduced motion skips
   all of it, a missing IntersectionObserver restores the reveal content, and
   without JavaScript none of it runs at all. The h1 cycles the phrases in
   AVRO.heroCycle (config.js) — each one is typed in, held, backspaced away
   and followed by the next, wrapping forever. A locale switch restarts the
   loop: i18n.js boots first, so its listener has already written the new
   language's phrase 0 when this module reads the list again.

   Dynamic renderers can call window.AVRO_MOTION.scan(root) after painting to
   bring newly-added .reveal nodes into scope.
   ========================================================================== */
(function () {
  'use strict';

  var doc = document;
  var root = doc.documentElement;

  function reduceMotion() {
    return window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  }

  function finePointer() {
    return window.matchMedia && window.matchMedia('(hover:hover) and (pointer:fine)').matches;
  }

  /* ---------------------------------------------------- scroll progress -- */
  function initProgress() {
    var bar = doc.querySelector('[data-progress]');
    if (!bar) return;
    var ticking = false;

    function paint() {
      ticking = false;
      var scroller = doc.scrollingElement || root;
      var max = scroller.scrollHeight - window.innerHeight;
      var pct = max > 1 ? (window.scrollY / max) * 100 : 0;
      bar.style.width = Math.max(0, Math.min(100, pct)) + '%';
    }

    function request() {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(paint);
    }

    window.addEventListener('scroll', request, { passive: true });
    window.addEventListener('resize', request, { passive: true });
    paint();
  }

  /* -------------------------------------------------------------- reveal -- */
  /* One observer feeds a document-order queue: elements join the queue as
     they touch the viewport, then reveal strictly top to bottom, one every
     STEP ms. An element the reader has already scrolled past releases
     instantly, so a fast scroll can never leave the final viewport waiting
     on a backlog of off-screen animations. */
  var revealIO = null;

  function scanReveal(scope) {
    if (!revealIO) return;
    var nodes = (scope || doc).querySelectorAll('.reveal:not(.is-visible)');
    for (var i = 0; i < nodes.length; i++) revealIO.observe(nodes[i]);
  }

  function initReveal() {
    if (reduceMotion()) return;
    if (!('IntersectionObserver' in window)) {
      /* The CSS only hides .reveal under html.js — drop the class so the
         content can never be stuck invisible without the observer. */
      root.classList.remove('js');
      return;
    }

    var STEP = 70;
    var queue = [];
    var pumpTimer = null;
    var clock = 0;

    function inDocumentOrder(a, b) {
      return (a.compareDocumentPosition(b) & 4) ? -1 : 1;
    }

    function onScreen(el) {
      var r = el.getBoundingClientRect();
      return r.bottom > 0 && r.top < (window.innerHeight || doc.documentElement.clientHeight);
    }

    function pump() {
      if (pumpTimer) return;
      var now = performance.now();
      while (queue.length) {
        var el = queue[0];
        if (el.classList.contains('is-visible')) {
          queue.shift();
          continue;
        }
        if (!onScreen(el)) {
          /* Scrolled past while it waited: nobody would see the motion, so
             it lands instantly and the cadence stays for what is on screen. */
          queue.shift();
          el.classList.add('is-visible');
          continue;
        }
        var wait = clock - now;
        if (wait > 4) {
          pumpTimer = setTimeout(function () { pumpTimer = null; pump(); }, wait);
          return;
        }
        queue.shift();
        el.classList.add('is-visible');
        clock = now + STEP;
        now = performance.now();
      }
    }

    function enqueue(nodes) {
      for (var i = 0; i < nodes.length; i++) queue.push(nodes[i]);
      queue.sort(inDocumentOrder);
      pump();
    }

    revealIO = new IntersectionObserver(function (entries) {
      var batch = [];
      for (var i = 0; i < entries.length; i++) {
        if (!entries[i].isIntersecting) continue;
        revealIO.unobserve(entries[i].target);
        batch.push(entries[i].target);
      }
      if (batch.length) enqueue(batch);
    }, { threshold: 0, rootMargin: '0px 0px -40px 0px' });

    scanReveal(doc);
  }

  /* ------------------------------------------------ h1 typing (loop) -- */
  /* Types a phrase, holds it, backspaces it away and moves to the next one,
     forever. Each phrase is split at its first comma: head in plain text,
     tail inside the gradient span (a comma-less phrase goes into the span
     whole). Phrase 0 is the text i18n.js and the shipped HTML already carry,
     so no-JS, pending and reduced-motion visitors see a settled headline. */
  function initTyping() {
    var h1 = doc.querySelector('.hero h1[data-i18n="hero.h1"]');
    if (!h1) return;

    var HOLD_MS = 2200;
    var GAP_MS = 450;
    var DELETE_MS = 24;

    var phrases = [];
    var caret = null;
    var reduced = reduceMotion();
    var state = {
      index: 0,
      phase: 'idle',
      ops: null,
      opIndex: 0,
      step: 46,
      stack: [],
      timer: null,
      waitFn: null,
      waitMs: 0,
      paused: false,
      sources: { hidden: doc.hidden, offscreen: false },
      typed: false
    };
    state.paused = !!(state.sources.hidden || state.sources.offscreen);

    function graphemes(text) {
      try {
        if (window.Intl && window.Intl.Segmenter) {
          var seg = new Intl.Segmenter(root.lang || 'en', { granularity: 'grapheme' });
          var out = [];
          var iter = seg.segment(text)[Symbol.iterator]();
          for (var r = iter.next(); !r.done; r = iter.next()) out.push(r.value.segment);
          return out;
        }
      } catch (e) { /* fall through to code points */ }
      return Array.from(text);
    }

    function currentLang() {
      var active = window.AVRO_I18N && window.AVRO_I18N.locale ? window.AVRO_I18N.locale() : null;
      return active || root.getAttribute('data-lang') || 'en';
    }

    /* The editorial list lives in config.js; if it is missing, fall back to
       whatever line the DOM carries so the page still settles sensibly. */
    function readPhrases() {
      var list = window.AVRO && Object.prototype.toString.call(window.AVRO.heroCycle) === '[object Array]'
        ? window.AVRO.heroCycle
        : null;
      if (list && list.length) {
        var lang = currentLang();
        var picked = [];
        for (var i = 0; i < list.length; i++) {
          var entry = list[i];
          var text = entry && typeof entry === 'object' ? (entry[lang] || entry.en) : entry;
          if (typeof text === 'string' && text.length) picked.push(text);
        }
        if (picked.length) return picked;
      }
      return [h1.textContent || ''];
    }

    function splitPhrase(phrase) {
      var i = phrase.indexOf(',');
      if (i === -1) return { head: '', tail: phrase };
      return { head: phrase.slice(0, i + 1), tail: phrase.slice(i + 1).replace(/^\s+/, '') };
    }

    function planPhrase(phrase) {
      var parts = splitPhrase(phrase);
      var ops = [];
      if (parts.head) ops.push({ kind: 'text', chars: graphemes(parts.head) });
      ops.push({ kind: 'br' });
      ops.push({ kind: 'span', chars: graphemes(parts.tail) });
      return ops;
    }

    /* Settled markup for one phrase, used for measuring and reduced motion. */
    function renderStatic(el, phrase) {
      while (el.firstChild) el.removeChild(el.firstChild);
      var parts = splitPhrase(phrase);
      if (parts.head) el.appendChild(doc.createTextNode(parts.head));
      el.appendChild(doc.createElement('br'));
      var span = doc.createElement('span');
      span.className = 'gradient';
      span.textContent = parts.tail;
      el.appendChild(span);
    }

    function caretEl() {
      if (!caret) {
        caret = doc.createElement('span');
        caret.className = 'type-caret';
        caret.setAttribute('aria-hidden', 'true');
      }
      return caret;
    }

    /* The tallest phrase wins, so nothing below the headline ever shifts as
       phrases of different lengths come and go. */
    function measure() {
      var previous = h1.innerHTML;
      var max = 0;
      for (var i = 0; i < phrases.length; i++) {
        renderStatic(h1, phrases[i]);
        var height = h1.offsetHeight;
        if (height > max) max = height;
      }
      h1.innerHTML = previous;
      h1.style.minHeight = max ? max + 'px' : '';
    }

    function staticRender() {
      state.index = 0;
      state.phase = 'static';
      renderStatic(h1, phrases[0]);
      h1.style.minHeight = '';
      h1.setAttribute('data-typed', '1');
      h1.setAttribute('data-cycle-phase', 'static');
      h1.setAttribute('data-cycle-index', '0');
    }

    function setPhase(phase) {
      state.phase = phase;
      h1.setAttribute('data-cycle-phase', phase);
      h1.setAttribute('data-cycle-index', String(state.index));
    }

    /* ---- timers, so a pause can re-arm the exact pending continuation --- */
    function clearWait() {
      if (state.timer) { clearTimeout(state.timer); state.timer = null; }
    }

    function schedule(fn, ms) {
      clearWait();
      state.waitFn = fn;
      state.waitMs = ms;
      if (!state.paused) state.timer = setTimeout(fn, ms);
    }

    function stopWait() {
      clearWait();
      state.waitFn = null;
      state.waitMs = 0;
    }

    function applyPause() {
      var paused = !!(state.sources.hidden || state.sources.offscreen);
      if (paused === state.paused) return;
      state.paused = paused;
      if (!state.waitFn) return;
      if (paused) clearWait();
      else state.timer = setTimeout(state.waitFn, state.waitMs);
    }

    function setSource(name, on) {
      state.sources[name] = !!on;
      applyPause();
    }

    /* --------------------------------------------------- the state machine */
    function beginPhrase(index) {
      stopWait();
      state.index = index % phrases.length;
      state.ops = planPhrase(phrases[state.index]);
      state.opIndex = 0;
      state.stack = [];
      var total = 0;
      for (var i = 0; i < state.ops.length; i++) {
        total += state.ops[i].chars ? state.ops[i].chars.length : 0;
      }
      state.step = Math.min(46, Math.max(18, Math.round(1700 / Math.max(total, 1))));
      while (h1.firstChild) h1.removeChild(h1.firstChild);
      h1.appendChild(caretEl());
      setPhase('type');
      schedule(typeTick, 60);
    }

    function typeTick() {
      var op = state.ops[state.opIndex];
      if (!op) { enterHold(); return; }

      if (op.kind === 'br') {
        var br = doc.createElement('br');
        h1.insertBefore(br, caretEl());
        state.stack.push({ kind: 'br', el: br });
        state.opIndex++;
        schedule(typeTick, 130);
        return;
      }

      var seg = state.stack[state.stack.length - 1];
      if (!seg || seg.opIndex !== state.opIndex) {
        var text = doc.createTextNode('');
        if (op.kind === 'span') {
          var span = doc.createElement('span');
          span.className = 'gradient';
          h1.insertBefore(span, caretEl());
          span.appendChild(text);
          seg = { kind: 'span', opIndex: state.opIndex, el: span, text: text, chars: op.chars, count: 0 };
        } else {
          h1.insertBefore(text, caretEl());
          seg = { kind: 'text', opIndex: state.opIndex, text: text, chars: op.chars, count: 0 };
        }
        state.stack.push(seg);
      }

      seg.text.nodeValue += seg.chars[seg.count];
      seg.count++;
      h1.appendChild(caretEl());
      if (seg.count < seg.chars.length) {
        schedule(typeTick, state.step);
      } else {
        state.opIndex++;
        schedule(typeTick, 150);
      }
    }

    function enterHold() {
      if (!state.typed) {
        state.typed = true;
        h1.setAttribute('data-typed', '1');
      }
      setPhase('hold');
      schedule(deleteTick, HOLD_MS);
    }

    function deleteTick() {
      if (state.phase !== 'delete') setPhase('delete');
      var seg = state.stack[state.stack.length - 1];
      if (!seg) {
        setPhase('gap');
        schedule(nextPhrase, GAP_MS);
        return;
      }

      if (seg.kind === 'br') {
        h1.removeChild(seg.el);
        state.stack.pop();
        schedule(deleteTick, 60);
        return;
      }

      if (seg.count > 0) {
        seg.count--;
        seg.text.nodeValue = seg.chars.slice(0, seg.count).join('');
        h1.appendChild(caretEl());
        schedule(deleteTick, DELETE_MS);
        return;
      }

      /* Emptied: drop the span shell or the leftover empty text node. */
      if (seg.kind === 'span') {
        h1.removeChild(seg.el);
        schedule(deleteTick, 60);
      } else {
        h1.removeChild(seg.text);
        schedule(deleteTick, DELETE_MS);
      }
      state.stack.pop();
    }

    function nextPhrase() {
      beginPhrase(state.index + 1);
    }

    /* ------------------------------------------------------------- boot -- */
    phrases = readPhrases();

    if (reduced) {
      staticRender();
      return;
    }

    doc.addEventListener('visibilitychange', function () {
      setSource('hidden', doc.hidden);
    });

    var hero = h1.closest ? h1.closest('.hero') : null;
    if (hero && 'IntersectionObserver' in window) {
      new IntersectionObserver(function (entries) {
        for (var i = 0; i < entries.length; i++) setSource('offscreen', !entries[i].isIntersecting);
      }, { threshold: 0 }).observe(hero);
    }

    /* A locale switch: i18n.js has already written the new language's text,
       so re-read the list and re-measure against the new script — then retype
       the phrase the loop is on, in the fresh language. The cycle position is
       never reset to 0; only a page load (or reload) starts over. */
    var booted = false;
    doc.addEventListener('avro:locale', function () {
      stopWait();
      booted = true;
      phrases = readPhrases();
      measure();
      beginPhrase(state.phase === 'gap' ? state.index + 1 : state.index);
    });

    var run = function () {
      booted = true;
      measure();
      beginPhrase(0);
    };
    var fonts = doc.fonts && doc.fonts.ready ? doc.fonts.ready : null;
    if (fonts && fonts.then) {
      fonts.then(function () { if (!booted) schedule(run, 240); },
                 function () { if (!booted) schedule(run, 240); });
    } else {
      schedule(run, 240);
    }
  }

  /* -------------------------------------------------------- hero particles -- */
  function initParticles() {
    var canvas = doc.querySelector('.hero-particles');
    if (!canvas || !canvas.getContext || reduceMotion()) return;
    var ctx = canvas.getContext('2d');
    if (!ctx) return;

    var GLYPHS = ['অ', 'আ', 'ই', 'ঈ', 'ক', 'খ', 'গ', 'ঘ', 'ব', 'ভ', 'ম', 'য', 'শ', 'প', 'ন', 'দ',];
    var COLORS = ['rgba(190, 145, 246, 0.79)', 'rgba(150, 37, 255, 0.79)', 'rgba(154, 75, 6, 0.65)', 'rgb(122, 79, 252)'];
    var DPR = Math.min(window.devicePixelRatio || 1, 2);
    var W = 1;
    var H = 1;
    var parts = [];
    var running = false;
    var raf = null;
    var mouseX = -9999;
    var mouseY = -9999;

    function resize() {
      W = Math.max(1, Math.round(canvas.offsetWidth * DPR));
      H = Math.max(1, Math.round(canvas.offsetHeight * DPR));
      canvas.width = W;
      canvas.height = H;
    }

    function make() {
      return {
        x: Math.random() * W,
        y: Math.random() * H,
        vx: (Math.random() - .5) * .22 * DPR,
        vy: (Math.random() - .5) * .22 * DPR,
        s: (16 + Math.random() * 22) * DPR,
        g: GLYPHS[Math.random() * GLYPHS.length | 0],
        c: COLORS[Math.random() * COLORS.length | 0],
        a: .25 + Math.random() * .45,
        r: Math.random() * Math.PI * 2,
        vr: (Math.random() - .5) * .003
      };
    }

    function frame() {
      if (!running) return;
      ctx.clearRect(0, 0, W, H);
      for (var i = 0; i < parts.length; i++) {
        var p = parts[i];
        p.x += p.vx;
        p.y += p.vy;
        p.r += p.vr;
        if (p.x < -80) p.x = W + 60; else if (p.x > W + 80) p.x = -60;
        if (p.y < -80) p.y = H + 60; else if (p.y > H + 80) p.y = -60;
        var dx = p.x - mouseX;
        var dy = p.y - mouseY;
        var d = Math.sqrt(dx * dx + dy * dy);
        if (d < 150 * DPR && d > 0) {
          p.x += (dx / d) * 1.3;
          p.y += (dy / d) * 1.3;
        }
        ctx.save();
        ctx.translate(p.x, p.y);
        ctx.rotate(p.r);
        ctx.font = '600 ' + p.s.toFixed(1) + 'px "Hind Siliguri", sans-serif';
        ctx.globalAlpha = p.a;
        ctx.fillStyle = p.c;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(p.g, 0, 0);
        ctx.restore();
      }
      raf = requestAnimationFrame(frame);
    }

    function play() {
      if (running) return;
      running = true;
      raf = requestAnimationFrame(frame);
    }

    function pause() {
      running = false;
      if (raf) cancelAnimationFrame(raf);
      raf = null;
    }

    resize();
    for (var i = 0; i < 34; i++) parts.push(make());

    window.addEventListener('resize', function () {
      resize();
      for (var j = 0; j < parts.length; j++) {
        parts[j].x = Math.min(parts[j].x, W);
        parts[j].y = Math.min(parts[j].y, H);
      }
    }, { passive: true });

    if (finePointer()) {
      var hero = canvas.parentElement;
      hero.addEventListener('mousemove', function (e) {
        var b = canvas.getBoundingClientRect();
        mouseX = (e.clientX - b.left) * DPR;
        mouseY = (e.clientY - b.top) * DPR;
      }, { passive: true });
      hero.addEventListener('mouseleave', function () { mouseX = mouseY = -9999; }, { passive: true });
    }

    if ('IntersectionObserver' in window) {
      var io = new IntersectionObserver(function (entries) {
        for (var k = 0; k < entries.length; k++) {
          if (entries[k].isIntersecting) play(); else pause();
        }
      }, { threshold: 0 });
      io.observe(canvas.parentElement);
    } else {
      play();
    }
  }

  /* --------------------------------------------------------------- marquee -- */
  function initMarquee() {
    var track = doc.querySelector('[data-marquee]');
    if (!track) return;
    var half = track.firstElementChild;
    if (!half) return;
    track.appendChild(half.cloneNode(true));
  }

  /* ---------------------------------------------------- magnetic buttons -- */
  function initMagnetic() {
    if (reduceMotion() || !finePointer()) return;
    var nodes = doc.querySelectorAll('.magnetic');
    for (var i = 0; i < nodes.length; i++) {
      (function (el) {
        el.addEventListener('mousemove', function (e) {
          var b = el.getBoundingClientRect();
          var x = e.clientX - b.left - b.width / 2;
          var y = e.clientY - b.top - b.height / 2;
          el.style.transform = 'translate(' + (x * .18).toFixed(1) + 'px,' + (y * .24).toFixed(1) + 'px)';
        });
        el.addEventListener('mouseleave', function () {
          el.style.transition = 'transform .3s ease';
          el.style.transitionDelay = '0ms';
          el.style.transform = '';
          setTimeout(function () {
            el.style.transition = '';
            el.style.transitionDelay = '';
          }, 330);
        });
      })(nodes[i]);
    }
  }

  /* ------------------------------------------------------------ card tilt -- */
  function initTilt() {
    if (reduceMotion() || !finePointer()) return;
    var cards = doc.querySelectorAll('.feature');
    for (var i = 0; i < cards.length; i++) {
      (function (card) {
        card.addEventListener('mousemove', function (e) {
          if (card.classList.contains('reveal') && !card.classList.contains('is-visible')) return;
          var b = card.getBoundingClientRect();
          var px = (e.clientX - b.left) / b.width - .5;
          var py = (e.clientY - b.top) / b.height - .5;
          card.style.transform = 'translateY(-4px) perspective(900px) rotateY(' +
            (px * 6).toFixed(2) + 'deg) rotateX(' + (-py * 6).toFixed(2) + 'deg)';
        });
        card.addEventListener('mouseleave', function () {
          card.style.transition = 'transform .35s ease';
          card.style.transitionDelay = '0ms';
          card.style.transform = '';
          setTimeout(function () {
            card.style.transition = '';
            card.style.transitionDelay = '';
          }, 380);
        });
      })(cards[i]);
    }
  }

  /* --------------------------------------------------------- back to top -- */
  /* The floating control fades in after about a screen of scrolling and
     glides home on click — instantly when reduced motion is on. */
  function initBackToTop() {
    var btn = doc.querySelector('[data-to-top]');
    if (!btn) return;
    var shown = false;
    var ticking = false;

    function update() {
      ticking = false;
      var next = (window.scrollY || root.scrollTop || 0) > 600;
      if (next === shown) return;
      shown = next;
      btn.classList.toggle('is-shown', shown);
    }

    function request() {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(update);
    }

    window.addEventListener('scroll', request, { passive: true });
    window.addEventListener('resize', request, { passive: true });
    btn.addEventListener('click', function () {
      window.scrollTo({ top: 0, behavior: reduceMotion() ? 'auto' : 'smooth' });
    });
    update();
  }

  /* ----------------------------------------------------------------- boot -- */
  window.AVRO_MOTION = { scan: scanReveal };

  function init() {
    initProgress();
    initReveal();
    initTyping();
    initParticles();
    initMarquee();
    initMagnetic();
    initTilt();
    initBackToTop();
  }

  if (doc.readyState === 'loading') {
    doc.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
