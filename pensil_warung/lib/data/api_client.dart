import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'api_exception.dart';

/// Thin wrapper over `package:http`: base URL, bearer token, JSON in and out,
/// error envelope -> [ApiException], socket/timeout -> [NetworkException].
class ApiClient {
  ApiClient({
    http.Client? client,
    String? baseUrl,
    this.token,
    this.onUnauthorized,
    this.timeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;
  final Duration timeout;

  /// Current bearer token, if signed in.
  String? Function()? token;

  /// Called after a `401 unauthorized` / `account_gone` on an authed request.
  VoidCallback? onUnauthorized;

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);
  Future<dynamic> post(String path, {Object? body}) =>
      _send('POST', path, body: body);
  Future<dynamic> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);
  Future<dynamic> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);
  Future<dynamic> delete(String path, {Object? body}) =>
      _send('DELETE', path, body: body);

  /// POST a single file as multipart form data.
  Future<dynamic> multipart(
    String path, {
    required String field,
    required List<int> bytes,
    required String filename,
    String method = 'POST',
  }) =>
      _send(method, path, file: http.MultipartFile.fromBytes(
        field,
        bytes,
        filename: filename,
      ));

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    http.MultipartFile? file,
  }) async {
    var uri = Uri.parse('$_baseUrl$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    final bearer = token?.call();
    final headers = {
      'Accept': 'application/json',
      if (bearer != null) 'Authorization': 'Bearer $bearer',
    };

    final http.BaseRequest request;
    if (file != null) {
      request = http.MultipartRequest(method, uri)..files.add(file);
    } else {
      final r = http.Request(method, uri);
      if (body != null) {
        r.headers['Content-Type'] = 'application/json';
        r.body = jsonEncode(body);
      }
      request = r;
    }
    request.headers.addAll(headers);

    final watch = Stopwatch()..start();
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException catch (e) {
      _log(method, path, 'timeout', watch);
      throw NetworkException(e);
    } on http.ClientException catch (e) {
      _log(method, path, 'network error', watch);
      throw NetworkException(e);
    } on Exception catch (e) {
      // dart:io SocketException and friends, without importing dart:io (web-safe).
      _log(method, path, 'network error', watch);
      throw NetworkException(e);
    }

    final requestId = response.headers['x-request-id'];
    final text = utf8.decode(response.bodyBytes);
    dynamic json;
    if (text.isNotEmpty) {
      try {
        json = jsonDecode(text);
      } on FormatException {
        json = null;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      _log(method, path, '${response.statusCode}', watch, requestId: requestId);
      return json;
    }

    final error = json is Map ? json['error'] : null;
    final e = ApiException(
      status: response.statusCode,
      code: error is Map && error['code'] is String
          ? error['code'] as String
          : 'unknown',
      message: error is Map && error['message'] is String
          ? error['message'] as String
          : 'Terjadi kesalahan. Coba lagi.',
      details: error is Map && error['details'] is Map
          ? Map<String, dynamic>.from(error['details'] as Map)
          : null,
      requestId: requestId,
    );
    _log(method, path, '${response.statusCode}', watch,
        code: e.code, requestId: requestId);
    if (bearer != null && (e.code == 'unauthorized' || e.code == 'account_gone')) {
      onUnauthorized?.call();
    }
    throw e;
  }

  // Never log tokens, passwords, id_tokens or bodies.
  void _log(String method, String path, String status, Stopwatch watch,
      {String? code, String? requestId}) {
    dev.log(
      '$method $path $status${code == null ? '' : ' $code'} ${requestId ?? '-'} ${watch.elapsedMilliseconds}ms',
      name: 'api',
    );
  }
}
