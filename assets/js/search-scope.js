/**
 * Scope MkDocs Material search results to the current platform.
 *
 * Detects the platform from the URL path (e.g. /react-native/, /flutter/)
 * and hides search results that belong to other platforms.
 */
(function () {
  var PLATFORMS = ["react-native", "cordova", "capacitor", "flutter"];

  function currentPlatform() {
    var path = window.location.pathname;
    for (var i = 0; i < PLATFORMS.length; i++) {
      if (path.indexOf("/" + PLATFORMS[i] + "/") !== -1) {
        return PLATFORMS[i];
      }
    }
    return null;
  }

  function filterResults() {
    var platform = currentPlatform();
    if (!platform) return; // on landing page — show all results

    var items = document.querySelectorAll("[data-md-component='search'] .md-search-result__item");
    items.forEach(function (item) {
      var link = item.querySelector("a");
      if (!link) return;
      var href = link.getAttribute("href") || "";
      // Show only results whose href contains the current platform path
      var match = false;
      for (var i = 0; i < PLATFORMS.length; i++) {
        if (href.indexOf("/" + PLATFORMS[i] + "/") !== -1) {
          match = (PLATFORMS[i] === platform);
          break;
        }
      }
      // Non-platform pages (e.g. home) — always show
      if (match || !PLATFORMS.some(function (p) { return href.indexOf("/" + p + "/") !== -1; })) {
        item.style.display = "";
      } else {
        item.style.display = "none";
      }
    });

    // Update the result count text
    var meta = document.querySelector("[data-md-component='search'] .md-search-result__meta");
    if (meta) {
      var visible = document.querySelectorAll("[data-md-component='search'] .md-search-result__item:not([style*='display: none'])");
      meta.textContent = visible.length + " matching document" + (visible.length !== 1 ? "s" : "");
    }
  }

  // Observe search result list for changes (results are injected dynamically)
  var observer = new MutationObserver(function () {
    filterResults();
  });

  // Wait for the search result container to exist, then observe it
  function init() {
    var container = document.querySelector("[data-md-component='search'] .md-search-result__list");
    if (container) {
      observer.observe(container, { childList: true, subtree: true });
    } else {
      // Retry until search DOM is ready
      setTimeout(init, 200);
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
