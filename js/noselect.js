/* ==========================================================================
   Text-selection guard. These pages are a product surface, not documents
   to copy from, so selection is blocked three ways:

   1. an injected !important stylesheet (covers a stale cached style.css
      that predates the user-select rule on body),
   2. a selectstart veto on the document (stops drag-selection and
      Ctrl+A before any range exists),
   3. a selectionchange sweep (clears anything that slips through, e.g.
      long-press selection on touch devices).

   No text inputs exist on these pages, so nothing legitimate is lost.
   ========================================================================== */
(function () {
  'use strict';

  var doc = document;

  function init() {
    var style = doc.createElement('style');
    style.textContent =
      'html *, html *::before, html *::after {' +
      ' -webkit-user-select: none !important;' +
      ' user-select: none !important;' +
      ' }';
    (doc.head || doc.documentElement).appendChild(style);

    doc.addEventListener('selectstart', function (e) {
      if (e.cancelable) e.preventDefault();
    });

    doc.addEventListener('selectionchange', function () {
      var get = window.getSelection;
      if (!get) return;
      var sel = get.call(window);
      if (sel && !sel.isCollapsed && sel.removeAllRanges) sel.removeAllRanges();
    });
  }

  if (doc.readyState === 'loading') {
    doc.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
