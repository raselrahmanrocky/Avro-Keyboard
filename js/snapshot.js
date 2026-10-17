/* ==========================================================================
   Persistent snapshot of the GitHub API.

   Every successful API response is written here, so the site keeps real
   project data on the visitor's own machine instead of only the snapshot that
   ships in data/. That gives three layers, tried in this order:

     1. a live GitHub API response            (always preferred, 10 min cache)
     2. the snapshot saved on an earlier visit (real data, honest capture date)
     3. the snapshot bundled in data/          (site's own last known good)

   So when the API is rate limited, offline or down, the visitor still sees
   actual numbers rather than placeholders — and never an invented one.

   Only public data is stored: the same counts, release notes and asset lists
   anybody can read on GitHub. Nothing here identifies the visitor.
   ========================================================================== */
window.AVRO_SNAP = (function () {
  'use strict';

  /* v2: "pushed" now means the main-branch head commit, not the repo-wide
     pushed_at. A stored v1 value could be a gh-pages deploy, so old entries
     are dropped rather than shown against their new meaning. */
  var KEY = 'avro-snap-v2';

  /* The anonymous GitHub API allows 60 requests/hour per visitor IP. Keeping
     each entry small means one busy release with a long changelog can never
     consume the whole localStorage budget and take the other entries with it. */
  var MAX_ENTRY_BYTES = 150000;
  var MAX_TOTAL_BYTES = 400000;

  var cache = null;
  var warned = false;

  function warn(message) {
    if (warned || !window.console || !console.warn) return;
    warned = true;
    console.warn('[snapshot] ' + message);
  }

  function readStore() {
    if (cache) return cache;
    cache = { v: 1, entries: {} };
    try {
      var raw = localStorage.getItem(KEY);
      if (raw) {
        var parsed = JSON.parse(raw);
        /* Shape check: a half-written or foreign value must not poison reads. */
        if (parsed && typeof parsed === 'object' && parsed.entries && typeof parsed.entries === 'object') {
          cache = { v: 1, entries: parsed.entries };
        }
      }
    } catch (e) {
      /* Corrupt JSON: start over rather than leaving the visitor stuck. */
      try { localStorage.removeItem(KEY); } catch (e2) { /* ignore */ }
      cache = { v: 1, entries: {} };
    }
    return cache;
  }

  function flush(store) {
    var total = 0;
    var names = Object.keys(store.entries);
    for (var i = 0; i < names.length; i++) {
      total += (store.entries[names[i]].raw || '').length;
      if (total > MAX_TOTAL_BYTES) {
        delete store.entries[names[i]];
      }
    }
    try {
      localStorage.setItem(KEY, JSON.stringify({ v: 1, entries: store.entries }));
      return true;
    } catch (e) {
      /* Quota or private mode. Snapshots are an enhancement, never required. */
      warn('could not persist; keeping the bundled data as the only fallback');
      return false;
    }
  }

  function isPlainObject(value) {
    return !!value && typeof value === 'object' && !Array.isArray(value);
  }

  /**
   * Read a saved snapshot.
   * @param {string} name
   * @returns {{data: Object, captured: string|null}|null}
   */
  function read(name) {
    var entry = readStore().entries[name];
    if (!entry || !isPlainObject(entry.data)) return null;
    return { data: entry.data, captured: entry.captured || null };
  }

  /**
   * Save (or extend) a snapshot. Values that came back `undefined`/`null` are
   * never allowed to erase a value learned earlier, so one partially failed
   * request cannot degrade a complete snapshot.
   * @param {string} name
   * @param {Object} patch
   */
  function write(name, patch) {
    if (!isPlainObject(patch)) return false;

    var store = readStore();
    var existing = store.entries[name];
    var base = (existing && isPlainObject(existing.data)) ? existing.data : {};
    var merged = {};
    var keys = Object.keys(base);
    var i;

    for (i = 0; i < keys.length; i++) merged[keys[i]] = base[keys[i]];

    var incoming = Object.keys(patch);
    var changed = false;
    for (i = 0; i < incoming.length; i++) {
      var value = patch[incoming[i]];
      if (value === undefined || value === null) continue;
      if (JSON.stringify(merged[incoming[i]]) !== JSON.stringify(value)) changed = true;
      merged[incoming[i]] = value;
    }
    if (!changed && existing) return false;

    var raw = JSON.stringify(merged);
    if (raw.length > MAX_ENTRY_BYTES) {
      warn('"' + name + '" exceeds ' + MAX_ENTRY_BYTES + ' bytes, not saving it');
      return false;
    }

    store.entries[name] = {
      captured: new Date().toISOString(),
      raw: raw,
      data: merged
    };
    return flush(store);
  }

  /** Where the data on screen came from, for an honest status line. */
  function info(name) {
    var entry = readStore().entries[name];
    if (!entry) return null;
    return { captured: entry.captured || null, bytes: (entry.raw || '').length };
  }

  function clear() {
    cache = null;
    try { localStorage.removeItem(KEY); } catch (e) { /* ignore */ }
  }

  return {
    KEY: KEY,
    read: read,
    write: write,
    info: info,
    clear: clear,
    names: function () { return Object.keys(readStore().entries); }
  };
})();
