import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:loqui/core/api/endpoints.dart';
import 'package:loqui/core/auth/token_storage.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class UnathorizedException extends ApiException {
  UnathorizedException(String message) : super(401, message);
}

/// Thin http wrapper. Authenticated calls attach bearer token and
/// on 401, try refresh token once before giving up.
/// A terminal 401 clears session via [onSessionExpired]
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required TokenStorage storage,
    http.Client? client,
    this.onSessionExpired,
  }) : _storage = storage,
       _http = client ?? http.Client();

  final String baseUrl;
  final TokenStorage _storage;
  final http.Client _http;
  final Future<void> Function()? onSessionExpired;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Map<String, String> get _json => {'Content-Type': 'application/json'};

  // ==== public ====

  Future<dynamic> postPublic(String path, Object body) async {
    final res = await _http.post(
      _uri(path),
      headers: _json,
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  /// Clears local tokens and best-effort revokes session (server-side)
  Future<void> logout() async {
    final refresh = await _storage.readRefresh();
    if (refresh != null) {
      try {
        await _http.post(
          _uri(Endpoints.logout),
          headers: _json,
          body: jsonEncode({'refresh_token': refresh}),
        );
      } catch (_) {
        //ignored: local logout proceeds regardless
      }
    }
    await _storage.clear();
  }

  // ==== authenticated ====

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _authed((h) => _http.get(_uri(path, query), headers: h));

  Future<dynamic> post(String path, Object body) => _authed(
    (h) => _http.post(_uri(path), headers: h, body: jsonEncode(body)),
  );

  Future<dynamic> patch(String path, Object body) => _authed(
    (h) => _http.patch(_uri(path), headers: h, body: jsonEncode(body)),
  );

  Future<dynamic> delete(String path) =>
      _authed((h) => _http.delete(_uri(path), headers: h));

  Future<dynamic> _authed(
    Future<http.Response> Function(Map<String, String> header) send,
  ) async {
    var res = await send(await _authHeaders());
    if (res.statusCode == 401) {
      if (!await _tryRefresh()) {
        await _expire();
        throw UnathorizedException('session expired');
      }
      res = await send(await _authHeaders());
      if (res.statusCode == 401) {
        await _expire();
        throw UnathorizedException('session expired');
      }
    }
    return _decode(res);
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await _storage.readAccess();
    return {..._json, if (token != null) 'Authorization': 'Bearer $token'};
  }

  Future<bool> _tryRefresh() async {
    final refresh = await _storage.readRefresh();
    if (refresh == null) return false;
    try {
      final res = await _http.post(
        _uri(Endpoints.refresh),
        headers: _json,
        body: jsonEncode({'refresh_token': refresh}),
      );
      if (res.statusCode != 200) return false;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      await _storage.saveTokens(
        data['access_token'] as String,
        data['refresh_token'] as String,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _expire() async {
    await _storage.clear();
    await onSessionExpired?.call();
  }

  dynamic _decode(http.Response res) {
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    dynamic body;
    if (res.body.isNotEmpty) {
      try {
        body = jsonDecode(res.body);
      } catch (_) {
        body = res.body;
      }
    }
    if (ok) return body;
    final msg = (body is Map && body['error'] is String)
        ? body['error'] as String
        : 'request failed';
    if (res.statusCode == 401) throw UnathorizedException(msg);
    throw ApiException(res.statusCode, msg);
  }

  void close() => _http.close();
}
