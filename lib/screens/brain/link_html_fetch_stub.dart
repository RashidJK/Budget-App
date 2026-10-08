/// Fallback for platforms that are neither dart:io nor the web — never used in
/// practice, but keeps the conditional import total.
Future<String?> fetchHtml(String url) async => null;
