/* ==========================================================================
   Privacy page — table of contents scroll-spy.

   Keeps the sidebar's Table of contents in sync with the section currently in
   view, the same behaviour js/changelog.js gives its version list: an
   IntersectionObserver watches every <section id> inside .doc, a deep link is
   honoured on load, and clicking a link activates it straight away instead of
   waiting for the scroll to settle.
   ========================================================================== */
(function () {
  'use strict';

  var nav = document.querySelector('.tag-nav');
  var doc = document.querySelector('.doc');
  if (!nav || !doc) return;

  var links = Array.prototype.slice.call(nav.querySelectorAll('a[href^="#"]'));
  var sections = doc.querySelectorAll('section[id]');
  if (!links.length || !sections.length) return;

  function setActive(id) {
    links.forEach(function (a) {
      a.setAttribute('aria-current', a.getAttribute('href') === '#' + id ? 'true' : 'false');
    });
  }

  links.forEach(function (a) {
    a.addEventListener('click', function () {
      setActive(a.getAttribute('href').slice(1));
    });
  });

  /* Matches changelog.js: the active band is the top fifth of the viewport
     down to 70% from the bottom, so an entry lights up as its heading scrolls
     in and stays lit while its section fills the screen. */
  if ('IntersectionObserver' in window) {
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) setActive(entry.target.id);
      });
    }, { rootMargin: '-20% 0px -70% 0px' });
    Array.prototype.forEach.call(sections, function (el) { observer.observe(el); });
  }

  /* At the very bottom of the page no section can move into the observer band
     any more, so the last entry would never light up on its own. */
  var last = sections[sections.length - 1];
  var ticking = false;
  window.addEventListener('scroll', function () {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(function () {
      ticking = false;
      if (window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2) {
        setActive(last.id);
      }
    });
  }, { passive: true });

  /* Opening privacy.html#storage must start with that entry active. */
  if (location.hash.length > 1) {
    var target = document.getElementById(location.hash.slice(1));
    if (target) setActive(target.id);
  }
})();
