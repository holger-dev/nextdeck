import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../config/sync_config.dart';
import '../services/log_service.dart';
import 'api_response.dart';
import 'request_deduplicator.dart';

class ApiClient {
  final http.Client _client;
  final RequestDeduplicator _dedup;
  ApiClient(this._client, this._dedup);

  Future<ApiResponse<T>> getJson<T>(
    String path, {
    Map<String, String>? query,
    String? etag,
    DateTime? lastModified,
    T Function(dynamic j)? decode,
  }) async {
    final uri = _buildUri(path, query);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (etag != null) 'If-None-Match': etag,
      if (lastModified != null) 'If-Modified-Since': _fmtHttpDate(lastModified),
    };
    final key = _dedupeKey(uri, headers);
    return _dedup.run<T>(key, () async {
      return _retry(() async {
        final t0 = DateTime.now();
        final logger = LogService();
        http.Response res;
        try {
          res = await _client.get(uri, headers: headers).timeout(kRequestTimeout);
        } catch (e) {
          logger.add(LogEntry(
            at: t0,
            method: 'GET',
            url: uri.toString(),
            status: null,
            durationMs: 0,
            requestBody: null,
            error: e.toString(),
          ));
          rethrow;
        }
        final dur = DateTime.now().difference(t0).inMilliseconds;
        final snippet = (res.body.length > 400) ? res.body.substring(0, 400) + '…' : res.body;
        logger.add(LogEntry(
          at: t0,
          method: 'GET',
          url: uri.toString(),
          status: res.statusCode,
          durationMs: dur,
          queuedMs: null,
          requestBody: null,
          responseSnippet: snippet,
        ));
        if (res.statusCode == 304) return ApiResponse.notModified<T>();
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final dynamic json = jsonDecode(res.body);
          final data = decode != null ? decode(json) : json as T;
          return ApiResponse.ok<T>(
            data,
            etag: res.headers['etag'] ?? res.headers['ETag'] ?? res.headers['Etag'],
            lastModified: _parseHttpDate(res.headers['last-modified'] ?? res.headers['Last-Modified']),
          );
        }
        throw HttpException('${res.statusCode}: ${res.reasonPhrase}');
      });
    });
  }

  Uri _buildUri(String path, Map<String, String>? query) {
    final p = path.startsWith('/') ? path : '/$path';
    // We assume server-relative for this client; caller should pass full paths including index.php or ocs prefixes
    var uri = Uri.parse(p);
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }
    if (p.startsWith('/ocs/') && !uri.queryParameters.containsKey('format')) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, 'format': 'json'});
    }
    return uri;
  }

  String _dedupeKey(Uri uri, Map<String, String> headers) => '${uri.toString()}|${headers['If-None-Match'] ?? ''}|${headers['If-Modified-Since'] ?? ''}';

  String _fmtHttpDate(DateTime dt) {
    // RFC 1123 format
    final wdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final utc = dt.toUtc();
    final wd = wdays[utc.weekday - 1];
    final mo = months[utc.month - 1];
    final dd = utc.day.toString().padLeft(2, '0');
    final hh = utc.hour.toString().padLeft(2, '0');
    final mm = utc.minute.toString().padLeft(2, '0');
    final ss = utc.second.toString().padLeft(2, '0');
    return '$wd, $dd $mo ${utc.year} $hh:$mm:$ss GMT';
  }

  DateTime? _parseHttpDate(String? s) {
    if (s == null || s.isEmpty) return null;
    try { return DateTime.parse(s); } catch (_) {}
    return null;
  }

  Future<ApiResponse<T>> _retry<T>(Future<ApiResponse<T>> Function() fn) async {
    int attempt = 0;
    while (true) {
      try {
        return await fn();
      } catch (e) {
        attempt++;
        if (attempt > kMaxRetries) rethrow;
        // Exponential backoff with jitter
        final base = kBaseBackoff.inMilliseconds * pow(2, attempt - 1);
        final jitter = Random().nextInt(400);
        final wait = Duration(milliseconds: base.toInt() + jitter);
        await Future.delayed(wait);
      }
    }
  }
}

class HttpException implements Exception {
  final String message;
  HttpException(this.message);
  @override
  String toString() => 'HttpException: $message';
}
