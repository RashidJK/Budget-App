// A tiny JSON POST that works on every platform without adding a package:
// dart:io on mobile/desktop, dart:html (browser fetch/XHR) on web.
export 'api_http_stub.dart'
    if (dart.library.io) 'api_http_io.dart'
    if (dart.library.html) 'api_http_web.dart';

/// The outcome of an HTTP call: the status code (0 = the request never
/// completed — offline, DNS, CORS) and the raw response body.
typedef HttpResult = ({int status, String body});
