/* ==========================================================================
   Light / dark theme.

   First-time visitors always start on the light theme; only a stored dark
   choice is reapplied, by a tiny inline script in <head> so the page never
   flashes the wrong palette. This file keeps the toggle button in sync
   (label included), persists the choice, and repaints the label when the
   language is switched.
   ========================================================================== */
(function () {
  'use strict';

  var cfg = window.AVRO || {};
  var storeKey = cfg.themeKey || 'avro-theme';
  var root = document.documentElement;

  function current() {
    return root.getAttribute('data-theme') === 'dark' ? 'dark' : 'light';
  }

  /* English is the fallback, so the toggle still works if i18n.js failed. */
  function label(key, fallback) {
    var i18n = window.AVRO_I18N;
    var text = i18n ? i18n.t(key) : key;
    return text === key ? fallback : text;
  }

  function paint(mode) {
    root.setAttribute('data-theme', mode);

    var btn = document.getElementById('themeBtn');
    if (!btn) return;

    var dark = mode === 'dark';
    var text = label(
      dark ? 'theme.toLight' : 'theme.toDark',
      dark ? 'Switch to light theme' : 'Switch to dark theme'
    );

    var icon = btn.querySelector('i');
    if (icon) icon.className = dark ? 'fa-solid fa-sun' : 'fa-solid fa-moon';
    btn.setAttribute('aria-pressed', dark ? 'true' : 'false');
    btn.setAttribute('aria-label', text);
    btn.setAttribute('title', text);
  }

  function persist(mode) {
    try { localStorage.setItem(storeKey, mode); } catch (e) { /* ignore */ }
  }

  paint(current());

  var btn = document.getElementById('themeBtn');
  if (btn) {
    btn.addEventListener('click', function () {
      var next = current() === 'dark' ? 'light' : 'dark';
      paint(next);
      persist(next);
    });
  }

  /* The button label is rendered by this module rather than by data-i18n
     attributes, so a language switch asks for one explicit repaint. */
  document.addEventListener('avro:locale', function () {
    paint(current());
  });
})();
