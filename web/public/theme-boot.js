/*
 * Appearance, before first paint.
 *
 * A separate file rather than an inline <script> in index.html: the backend serves the app under
 * `script-src 'self'` (see backend/src/main.ts), which blocks inline execution outright. Inline
 * worked under `vite dev`, which sends no CSP, and silently did nothing in the build that people
 * actually run — the Playwright smoke journey is what caught it.
 *
 * It lives in `public/` so Vite copies it verbatim instead of bundling it, and it is loaded
 * blocking (no `defer`, no `type="module"`) so it runs before anything is drawn. The palette and
 * light/dark choice live in localStorage, and anything that reads them after the bundle loads
 * paints the default warm paper first and then snaps to the chosen one. A flash of the wrong theme
 * is a poor greeting anywhere and a worse one at night.
 *
 * `src/theme.ts` owns the same logic for the rest of the session and is the file to change; this is
 * deliberately the smallest possible copy of the read-and-apply step, and it touches nothing but
 * two attributes on <html>.
 */
(function () {
  var palette = 'paper';
  var mode = 'system';
  try {
    var stored = JSON.parse(localStorage.getItem('mood-diary:appearance') || '{}');
    if (['paper', 'sage', 'dusk'].indexOf(stored.palette) !== -1) palette = stored.palette;
    if (['system', 'light', 'dark'].indexOf(stored.mode) !== -1) mode = stored.mode;
  } catch (e) {
    /* blocked or corrupt storage: the defaults are a perfectly good diary. */
  }
  var dark =
    mode === 'dark' ||
    (mode === 'system' &&
      window.matchMedia &&
      window.matchMedia('(prefers-color-scheme: dark)').matches);
  document.documentElement.dataset.palette = palette;
  document.documentElement.dataset.mode = dark ? 'dark' : 'light';
})();
