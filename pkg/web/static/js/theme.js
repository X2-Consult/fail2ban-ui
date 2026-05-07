"use strict";

var themeMediaQuery = null;

function isAutoDarkEnabled() {
  return document.documentElement.getAttribute('data-auto-dark') === 'true';
}

function getSystemTheme() {
  if (!isAutoDarkEnabled()) {
    return 'light';
  }
  if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
    return 'dark';
  }
  return 'light';
}

function applyTheme(theme) {
  var resolvedTheme = theme === 'dark' ? 'dark' : 'light';
  var root = document.documentElement;

  root.setAttribute('data-theme', resolvedTheme);
  syncFavicons(resolvedTheme);
}

function syncFavicons(theme) {
  var resolvedTheme = theme === 'dark' ? 'dark' : 'light';
  var hrefAttr = resolvedTheme === 'dark' ? 'data-dark-href' : 'data-light-href';
  var favicon = document.getElementById('appFavicon');
  var appleTouchIcon = document.getElementById('appAppleTouchIcon');
  var faviconHref = favicon ? favicon.getAttribute(hrefAttr) : '';
  var appleHref = appleTouchIcon ? appleTouchIcon.getAttribute(hrefAttr) : '';

  if (favicon && faviconHref) {
    favicon.setAttribute('href', faviconHref);
  }
  if (appleTouchIcon && appleHref) {
    appleTouchIcon.setAttribute('href', appleHref);
  }
}

function syncSystemTheme() {
  if (document.body && document.body.classList.contains('lotr-mode')) {
    return;
  }
  applyTheme(getSystemTheme());
}

function updateThemeToggleIcons(theme) {
  var isDark = theme === 'dark';
  var icon = document.getElementById('themeToggleIcon');
  var iconMobile = document.getElementById('themeToggleIconMobile');
  var label = document.getElementById('themeToggleLabelMobile');
  if (icon)       { icon.className       = isDark ? 'fas fa-sun text-sm' : 'fas fa-moon text-sm'; }
  if (iconMobile) { iconMobile.className = isDark ? 'fas fa-sun' : 'fas fa-moon'; }
  if (label)      { label.textContent    = isDark ? 'Light Mode' : 'Dark Mode'; }
}

function toggleTheme() {
  var current = document.documentElement.getAttribute('data-theme');
  var next = current === 'dark' ? 'light' : 'dark';
  try { localStorage.setItem('f2b-theme', next); } catch (e) {}
  applyTheme(next);
  updateThemeToggleIcons(next);
}

function initThemeManager() {
  syncSystemTheme();
  updateThemeToggleIcons(document.documentElement.getAttribute('data-theme') || 'light');
  if (!isAutoDarkEnabled()) {
    return;
  }
  if (!window.matchMedia || themeMediaQuery) {
    return;
  }

  themeMediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
  if (typeof themeMediaQuery.addEventListener === 'function') {
    themeMediaQuery.addEventListener('change', function() {
      syncSystemTheme();
      updateThemeToggleIcons(document.documentElement.getAttribute('data-theme') || 'light');
    });
  }
}

window.initThemeManager = initThemeManager;
window.syncSystemTheme = syncSystemTheme;
window.toggleTheme = toggleTheme;
