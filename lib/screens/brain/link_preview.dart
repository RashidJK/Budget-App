import 'link_html_fetch.dart';

/// A link's fetched preview — its page title and cover image, either of which
/// may be missing.
class LinkPreviewData {
  const LinkPreviewData({this.title, this.image});

  final String? title;
  final String? image;

  bool get isEmpty => (title?.isEmpty ?? true) && (image?.isEmpty ?? true);
}

/// Best-effort Open Graph scraper. Fetches a page's `<head>` (directly on
/// mobile/desktop, via a CORS proxy on web — see link_html_fetch.dart), pulls
/// out og:title / og:image (falling back to the `<title>` tag), and caches the
/// result in memory. A couple of regexes do the parsing — no package needed.
/// Every failure path returns an empty preview, so the UI keeps its favicon.
class LinkPreview {
  LinkPreview._();

  static final Map<String, LinkPreviewData> _cache = {};
  static final Map<String, Future<LinkPreviewData>> _inflight = {};

  static Future<LinkPreviewData> fetch(String rawUrl) {
    final cached = _cache[rawUrl];
    if (cached != null) return Future.value(cached);
    return _inflight[rawUrl] ??= _fetch(rawUrl).then((data) {
      _cache[rawUrl] = data;
      _inflight.remove(rawUrl);
      return data;
    });
  }

  static Future<LinkPreviewData> _fetch(String rawUrl) async {
    var url = rawUrl.trim();
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) {
      url = 'https://$url';
    }
    final Uri uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return const LinkPreviewData();
    }
    // Platform-specific fetch: direct on mobile/desktop, CORS-proxied on web.
    final html = await fetchHtml(url);
    if (html == null || html.isEmpty) return const LinkPreviewData();
    return parse(html, base: uri);
  }

  /// Extracts a preview from raw HTML — public so it can be unit-tested without
  /// a network round-trip. [base] resolves a relative og:image against the page.
  static LinkPreviewData parse(String html, {Uri? base}) {
    final image = _meta(html, 'og:image');
    return LinkPreviewData(
      title: _meta(html, 'og:title') ?? _titleTag(html),
      image: base == null ? image : _absolute(image, base),
    );
  }

  static String? _meta(String html, String property) {
    // Handle both attribute orders: property-then-content and content-then-property.
    for (final re in [
      RegExp(
        '<meta[^>]+(?:property|name)=["\']$property["\'][^>]+content=["\']([^"\']*)["\']',
        caseSensitive: false,
      ),
      RegExp(
        '<meta[^>]+content=["\']([^"\']*)["\'][^>]+(?:property|name)=["\']$property["\']',
        caseSensitive: false,
      ),
    ]) {
      final match = re.firstMatch(html);
      final value = _decode(match?.group(1));
      if (value != null) return value;
    }
    return null;
  }

  static String? _titleTag(String html) {
    final match = RegExp(
      r'<title[^>]*>([^<]*)</title>',
      caseSensitive: false,
    ).firstMatch(html);
    return _decode(match?.group(1)?.trim());
  }

  static String? _absolute(String? value, Uri base) {
    if (value == null || value.isEmpty) return null;
    try {
      return base.resolve(value).toString();
    } catch (_) {
      return value;
    }
  }

  static String? _decode(String? s) {
    if (s == null) return null;
    final out = s
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
    return out.isEmpty ? null : out;
  }
}
