/* ==========================================================================
   Mobile navigation.

   Below 1160px style.css hides the full link row and shows the burger
   button; tapping it opens the same links as a full-height panel under the
   sticky bar (the approved mobile mockup) with the Download call to action
   pinned to the bottom. The button carries aria-expanded/aria-controls,
   Escape closes and returns focus, a link tap closes, and crossing back to
   the wide layout always closes, so the panel can never linger over the
   desktop header. While it is open, Tab cycles the header controls and the
   panel links so the keyboard cannot wander into the page behind.
   ========================================================================== */
(function () {
  'use strict';

  var root = document.documentElement;
  var btn = document.querySelector('[data-menu-toggle]');
  var nav = document.getElementById('mainNav');
  if (!btn || !nav) return;

  var bar = btn.closest ? btn.closest('.topbar') : null;
  var wide = window.matchMedia ? window.matchMedia('(min-width: 1160px)') : null;

  function isOpen() {
    return root.classList.contains('menu-open');
  }

  function setIcon(name) {
    var icon = btn.querySelector('i');
    if (icon) icon.className = 'fa-solid ' + name;
  }

  function open() {
    /* The sticky bar's backdrop-filter makes it the containing block of the
       absolutely positioned panel; the measured height keeps the panel glued
       to the bar's lower edge whatever the breakpoint does. */
    if (bar) nav.style.setProperty('--navh', bar.offsetHeight + 'px');
    root.classList.add('menu-open');
    btn.setAttribute('aria-expanded', 'true');
    setIcon('fa-xmark');
    var first = nav.querySelector('a');
    if (first) first.focus();
  }

  function close(restoreFocus) {
    if (!isOpen()) return;
    root.classList.remove('menu-open');
    btn.setAttribute('aria-expanded', 'false');
    setIcon('fa-bars');
    if (restoreFocus) btn.focus();
  }

  btn.addEventListener('click', function () {
    if (isOpen()) close(false);
    else open();
  });

  /* Any link tap closes the panel before the browser follows the href. */
  nav.addEventListener('click', function (e) {
    var link = e.target && e.target.closest ? e.target.closest('a') : null;
    if (link) close(false);
  });

  /* The card is compact, so the page behind stays tappable; tapping it
     closes the menu. */
  document.addEventListener('click', function (e) {
    if (!isOpen()) return;
    if (bar && e.target && bar.contains(e.target)) return;
    close(false);
  });

  document.addEventListener('keydown', function (e) {
    if (!isOpen()) return;
    if (e.key === 'Escape') {
      close(true);
      return;
    }
    if (e.key !== 'Tab' || !bar) return;
    /* Keep the keyboard inside the open header: the panel links and the
       bar's own controls, in document order. */
    var list = bar.querySelectorAll('a[href], button:not([disabled])');
    var items = [];
    for (var i = 0; i < list.length; i++) {
      if (list[i].offsetParent !== null) items.push(list[i]);
    }
    if (!items.length) return;
    var first = items[0];
    var last = items[items.length - 1];
    var active = document.activeElement;
    if (e.shiftKey) {
      if (active === first || items.indexOf(active) === -1) {
        e.preventDefault();
        last.focus();
      }
    } else if (active === last) {
      e.preventDefault();
      first.focus();
    }
  });

  /* A rotation or resize while the panel is open re-measures the bar. */
  window.addEventListener('resize', function () {
    if (isOpen() && bar) nav.style.setProperty('--navh', bar.offsetHeight + 'px');
  }, { passive: true });

  var onChange = function (e) {
    if (e.matches) close(false);
  };
  if (wide) {
    if (wide.addEventListener) wide.addEventListener('change', onChange);
    else if (wide.addListener) wide.addListener(onChange);
  }
})();
