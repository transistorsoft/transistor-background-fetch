/* Lucide icon injection for setup page headings and TOC entries.
 *
 * Reads BGEO_TOC_ICONS (from toc-icons.js) for TOC icons on reference pages.
 * Injects Lucide icons into setup page headings based on SETUP_HEADING_ICONS map.
 *
 * Material for MkDocs duplicates the secondary nav (desktop sidebar + mobile
 * drawer), so we process every .md-nav--secondary element on the page.
 */
(function () {
  'use strict';

  /* Convert kebab-case icon name to PascalCase for lucide.icons lookup. */
  function toPascalCase(name) {
    return name.replace(/(^|-)([a-z0-9])/g, function (_, __, c) { return c.toUpperCase(); });
  }

  /* Build a Lucide SVG element for a given icon name (kebab-case). */
  function buildIcon(iconName) {
    if (!iconName || typeof lucide === 'undefined') { return null; }
    var key = toPascalCase(iconName);
    var iconDef = lucide.icons && lucide.icons[key];
    if (!iconDef) { return null; }
    return lucide.createElement(iconDef);
  }

  /* Inject a Lucide SVG icon before the label text inside a TOC <a> element. */
  function injectIcon(link, iconName) {
    if (!iconName || link.querySelector('.bgeo-toc-icon')) { return; }
    var svg = buildIcon(iconName);
    if (!svg) { return; }
    svg.classList.add('bgeo-toc-icon');
    svg.setAttribute('aria-hidden', 'true');
    link.insertBefore(svg, link.firstChild);
  }

  /* Inject a Lucide SVG icon into a page heading. */
  function injectHeadingIcon(heading, iconName) {
    if (!iconName || heading.querySelector('.bgeo-heading-icon')) { return; }
    var svg = buildIcon(iconName);
    if (!svg) { return; }
    svg.classList.add('bgeo-heading-icon');
    svg.setAttribute('aria-hidden', 'true');
    heading.insertBefore(svg, heading.firstChild);
  }

  /* Extract visible label text from a TOC <a> (strip whitespace). */
  function linkLabel(link) {
    var span = link.querySelector('.md-ellipsis');
    return span ? span.textContent.trim() : link.textContent.trim();
  }

  /* Process one .md-nav--secondary element for TOC icons. */
  function initToc(toc) {
    var icons = (typeof BGEO_TOC_ICONS !== 'undefined') ? BGEO_TOC_ICONS : {};

    // Top-level TOC entries (H2 sections: Events, Methods, Properties, Constants)
    toc.querySelectorAll(':scope > .md-nav__list > .md-nav__item > .md-nav__link')
      .forEach(function (link) {
        injectIcon(link, icons[linkLabel(link)]);
      });
  }

  // ── Setup page heading icons ─────────────────────────────────────────────

  /* Map heading text → Lucide icon name, or "platform:<slug>" for SVG icons. */
  var SETUP_HEADING_ICONS = {
    // Common
    'Installation':                   'package',
    'Example':                        'code-2',
    // Platform section headers
    'iOS Setup':                      'platform:ios',
    'Android Setup':                  'platform:android',
    'iOS & Android Setup':            'platform:ios',
    // React Native / Expo tabs
    'React Native':                   'platform:react-native',
    'Expo':                           'platform:expo',
    // iOS sub-sections
    'CocoaPods':                      'layers',
    'Background Modes':               'radio',
    'Info.plist':                     'file-code',
    // Android sub-sections
    // Expo sub-sections
    'app.json':                       'file-json',
    'app.json / app.config.js':       'file-json',
    'Prebuild':                       'hammer',
  };

  /* Inject a platform SVG icon (span with data-platform, styled via CSS). */
  function injectPlatformHeadingIcon(heading, slug) {
    if (heading.querySelector('.bgeo-platform-heading-icon')) { return; }
    var span = document.createElement('span');
    span.className = 'bgeo-platform-heading-icon';
    span.setAttribute('data-platform', slug);
    span.setAttribute('aria-hidden', 'true');
    heading.insertBefore(span, heading.firstChild);
  }

  function initSetupHeadings() {
    var article = document.querySelector('.md-content article');
    if (!article) { return; }

    article.querySelectorAll('h2, h3, h4').forEach(function (h) {
      if (h.querySelector('.bgeo-heading-icon, .bgeo-platform-heading-icon')) { return; }
      // Strip the MkDocs permalink anchor (¶) before matching
      var clone = h.cloneNode(true);
      var hl = clone.querySelector('.headerlink');
      if (hl) { hl.remove(); }
      var text = clone.textContent.trim();
      var icon = SETUP_HEADING_ICONS[text];
      if (!icon) { return; }
      if (icon.indexOf('platform:') === 0) {
        injectPlatformHeadingIcon(h, icon.slice(9));
      } else {
        injectHeadingIcon(h, icon);
      }
    });
  }

  window.addEventListener('load', function () {
    document.querySelectorAll('.md-nav--secondary').forEach(initToc);
    initSetupHeadings();
  });
}());
