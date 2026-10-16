/* ==========================================================================
   "commits ahead of the official baseline" markers.

   This number appears in the comparison cards, in a note, and in the footer of
   every page, so it gets its own tiny module rather than being duplicated.
   Requests are memoised in js/github.js, so calling liveStats() again here
   costs nothing extra.
   ========================================================================== */
(function () {
  'use strict';

  var GH = window.AVRO_GH;
  var value = null;

  function fill(next) {
    if (typeof next === 'number' && isFinite(next)) value = next;
    if (typeof value !== 'number') return;

    /* Queried on every fill rather than once at load: the sentences carrying
       these markers are translated prose, so switching language replaces the
       elements themselves. */
    var targets = document.querySelectorAll('[data-ahead-note]');
    for (var i = 0; i < targets.length; i++) {
      targets[i].textContent = GH.fmt.num(value);
    }
  }

  (async function run() {
    var snapshot = await GH.snapshotStats();
    if (snapshot && snapshot.data) fill(snapshot.data.ahead);

    var live = await GH.liveStats();
    if (live.live && live.data) fill(live.data.ahead);
  })();

  document.addEventListener('avro:locale', function () { fill(); });
})();
