// Fetches a page's HTML for Open Graph scraping, the right way per platform:
// a direct request via dart:io on mobile/desktop, and a CORS-proxied request
// from the browser on web (which can't fetch cross-origin HTML directly).
export 'link_html_fetch_stub.dart'
    if (dart.library.io) 'link_html_fetch_io.dart'
    if (dart.library.html) 'link_html_fetch_web.dart';
