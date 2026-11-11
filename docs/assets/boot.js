/* Page bootstrap.
 *
 * Replaces the per-page inline <script> blocks that used to call
 * AIMTNav.initNav('nav-container', '<page>.html'). Inline script is what forced
 * script-src to allow 'unsafe-inline' in the CSP; moving it out here lets the
 * site run under a strict `script-src 'self'`. The page name is derived from the
 * document path, which is exactly what those blocks hardcoded.
 */
document.addEventListener('DOMContentLoaded', function () {
    var page = (location.pathname.split('/').pop() || 'index.html') || 'index.html';
    if (window.AIMTNav && typeof window.AIMTNav.initNav === 'function') {
        window.AIMTNav.initNav('nav-container', page);
    }
});
