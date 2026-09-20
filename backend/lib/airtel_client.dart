import 'dart:convert';

import 'package:http/http.dart' as http;

/// Talks to Airtel OpenAPI: mints and caches an OAuth2 bearer token, then calls
/// the Transactions-Summary endpoint. All the secret handling lives here, on the
/// server — the mobile app never sees any of it.
class AirtelClient {
  AirtelClient({
    required this.baseUrl,
    required this.clientId,
    required this.clientSecret,
    this.country = 'TZ',
    this.currency = 'TZS',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// e.g. https://openapi.airtel.co.tz (prod) or https://openapiuat.airtel.co.tz
  final String baseUrl;
  final String clientId;
  final String clientSecret;
  final String country;
  final String currency;

  final http.Client _http;

  String? _token;
  DateTime? _expiry;

  /// A valid bearer token, minted on first use and refreshed a minute before it
  /// expires so an in-flight call never carries a stale one.
  Future<String> _accessToken() async {
    final token = _token;
    final expiry = _expiry;
    if (token != null && expiry != null && DateTime.now().isBefore(expiry)) {
      return token;
    }

    final res = await _http.post(
      Uri.parse('$baseUrl/auth/oauth2/token'),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'client_id': clientId,
        'client_secret': clientSecret,
        'grant_type': 'client_credentials',
      }),
    );
    if (res.statusCode >= 400) {
      throw Exception('Airtel token request failed (${res.statusCode}): '
          '${res.body}');
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final fresh = json['access_token'] as String?;
    if (fresh == null) {
      throw Exception('Airtel token response had no access_token: ${res.body}');
    }
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    _token = fresh;
    _expiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
    return fresh;
  }

  /// GET /merchant/v1/transactions for the window, returning Airtel's raw JSON
  /// body so the app's existing parser handles it unchanged. Retries once on a
  /// 401 in case the cached token was revoked early.
  Future<String> transactions({
    required String from,
    required String to,
    String limit = '100',
    String offset = '0',
  }) async {
    final uri = Uri.parse('$baseUrl/merchant/v1/transactions').replace(
      queryParameters: {
        'from': from,
        'to': to,
        'limit': limit,
        'offset': offset,
      },
    );

    Future<http.Response> call(String token) => _http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        'x-country': country,
        'x-currency': currency,
      },
    );

    var res = await call(await _accessToken());
    if (res.statusCode == 401) {
      _token = null;
      _expiry = null;
      res = await call(await _accessToken());
    }
    if (res.statusCode >= 400) {
      throw Exception('Airtel transactions failed (${res.statusCode}): '
          '${res.body}');
    }
    return res.body;
  }

  void close() => _http.close();
}
