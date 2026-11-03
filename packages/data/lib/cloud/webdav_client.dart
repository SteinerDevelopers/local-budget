// E7b §3.1/§3.2 — the WebDAV transport for own-cloud backup. Deliberately
// dumb: no caching, no local manifest (the listing IS the truth), Basic
// auth only (NAS app-passwords are the target user), and the §3.1 URL
// rule enforced here so no caller can dial out to a plain-HTTP public
// host by accident. Encryption happens upstream in createBackup — this
// client never sees plaintext ledger bytes.
import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'cloud_target.dart';
import 'retention.dart';

/// §3.1: HTTPS always; plain HTTP only for RFC1918/loopback hosts — and
/// then only with the red-banner warning the UI owes the user.
enum WebdavUrlStatus { ok, insecureLan, rejected }

class WebdavUrlCheck {
  const WebdavUrlCheck(this.status, this.reason);
  final WebdavUrlStatus status;
  final String? reason;
  bool get allowed => status != WebdavUrlStatus.rejected;
  bool get needsBanner => status == WebdavUrlStatus.insecureLan;
}

bool _isRfc1918(String host) {
  final parts = host.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null)) return false;
  final a = parts[0]!, b = parts[1]!;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}

bool _isLoopback(String host) {
  if (host == 'localhost' || host.endsWith('.localhost')) return true;
  if (host == '::1') return true;
  return host.startsWith('127.');
}

WebdavUrlCheck checkWebdavUrl(String raw) {
  final Uri uri;
  try {
    uri = Uri.parse(raw);
  } on FormatException {
    return const WebdavUrlCheck(WebdavUrlStatus.rejected, 'Not a valid URL.');
  }
  if (uri.userInfo.isNotEmpty) {
    return const WebdavUrlCheck(
      WebdavUrlStatus.rejected,
      'Put user and password in their own fields, not the URL.',
    );
  }
  if (uri.host.isEmpty) {
    return const WebdavUrlCheck(WebdavUrlStatus.rejected, 'Missing host.');
  }
  if (uri.scheme == 'https') {
    return const WebdavUrlCheck(WebdavUrlStatus.ok, null);
  }
  if (uri.scheme == 'http') {
    final host = uri.host;
    if (_isLoopback(host) || _isRfc1918(host)) {
      return const WebdavUrlCheck(
        WebdavUrlStatus.insecureLan,
        'Plain HTTP: readable to anything on your LAN. Fine for a home '
        'NAS you own — the banner stays on screen.',
      );
    }
    return const WebdavUrlCheck(
      WebdavUrlStatus.rejected,
      'Plain HTTP is only allowed for RFC1918/loopback hosts; use https '
      'for everything else.',
    );
  }
  return const WebdavUrlCheck(
    WebdavUrlStatus.rejected,
    'Only http and https endpoints are supported.',
  );
}

class WebdavException implements Exception {
  const WebdavException(this.method, this.url, this.statusCode, [this.detail]);
  final String method;
  final Uri url;
  final int statusCode;
  final String? detail;
  @override
  String toString() =>
      'WebdavException($method $statusCode $url${detail == null ? '' : ': $detail'})';
}

/// Retryable transport/server failures — [WebdavClient.put] backs off and
/// re-PUTs (partial-upload recovery, §6); everything else fails fast.
class WebdavTransportException implements Exception {
  const WebdavTransportException(this.method, this.url, this.cause);
  final String method;
  final Uri url;
  final Object cause;
  @override
  String toString() => 'WebdavTransportException($method $url: $cause)';
}

class WebdavClient implements CloudTarget {
  WebdavClient({
    required String baseUrl,
    String? user,
    String? password,
    http.Client? client,
    Future<void> Function(Duration)? sleep,
    this.retries = 2,
  }) : base = Uri.parse(baseUrl),
       _auth = (user == null || user.isEmpty)
           ? null
           : 'Basic ${base64Encode(utf8.encode('$user:$password'))}',
       _client = client ?? http.Client(),
       _sleep = sleep ?? Future.delayed;

  final Uri base;
  final String? _auth;
  final http.Client _client;
  final Future<void> Function(Duration) _sleep;
  final int retries;

  void close() => _client.close();

  Uri _url(String relPath) {
    final trimmed = base.path.endsWith('/') ? base.path : '${base.path}/';
    return base.replace(
      path:
          '$trimmed${relPath.startsWith('/') ? relPath.substring(1) : relPath}',
    );
  }

  Map<String, String> _headers([Map<String, String>? extra]) {
    final h = <String, String>{if (_auth != null) 'Authorization': _auth};
    if (extra != null) h.addAll(extra);
    return h;
  }

  Future<http.Response> _send(
    String method,
    Uri url, {
    Map<String, String>? headers,
    List<int>? body,
  }) async {
    final request = http.Request(method, url)
      ..headers.addAll(_headers(headers));
    if (body != null) request.bodyBytes = body;
    final streamed = await _client.send(request);
    return http.Response.fromStream(streamed);
  }

  /// MKCOL [relPath]; 405/403-with-existing both mean "folder is there"
  /// (§6 calls out the MKCOL-405 dance explicitly).
  Future<void> ensureCollection(String relPath) async {
    final r = await _send('MKCOL', _url(relPath));
    if (r.statusCode == 201 || r.statusCode == 405 || r.statusCode == 204) {
      return;
    }
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw WebdavException(
        'MKCOL',
        r.request?.url ?? _url(relPath),
        r.statusCode,
        'check the user/password',
      );
    }
    throw WebdavException('MKCOL', _url(relPath), r.statusCode);
  }

  /// PROPFIND Depth:1 over [relPath]. The requesting folder itself is
  /// dropped; every child becomes a [CloudObject] with a dest-relative
  /// [CloudObject.path]. Foreign files are listed too — retention decides.
  Future<List<CloudObject>> list(String relPath) async {
    const body =
        '<?xml version="1.0" encoding="utf-8"?>'
        '<d:propfind xmlns:d="DAV:"><d:prop>'
        '<d:displayname/><d:getcontentlength/><d:getlastmodified/>'
        '</d:prop></d:propfind>';
    final r = await _send(
      'PROPFIND',
      _url(relPath),
      headers: {'Content-Type': 'application/xml', 'Depth': '1'},
      body: utf8.encode(body),
    );
    if (r.statusCode != 207 && r.statusCode != 200) {
      throw WebdavException('PROPFIND', _url(relPath), r.statusCode);
    }
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(r.body);
    } on XmlException {
      throw WebdavException(
        'PROPFIND',
        _url(relPath),
        r.statusCode,
        'body is not valid multistatus XML',
      );
    }
    final dirRel = _normalizeRel(relPath);
    final out = <CloudObject>[];
    for (final resp in _local(doc, 'response')) {
      final hrefEl = _local(resp, 'href').firstOrNull;
      if (hrefEl == null) continue;
      final rel = _relFromHref(hrefEl.innerText);
      if (rel.isEmpty || rel == dirRel || _normalizeRel(rel) == dirRel) {
        continue; // the collection itself
      }
      final name = rel.split('/').last;
      if (name.isEmpty) continue; // nested collection marker
      // Props live under response/propstat/prop; DAV: prefixes mean we
      // must match by LOCAL name, so every lookup goes through [_local].
      final len =
          int.tryParse(
            _local(resp, 'getcontentlength').firstOrNull?.innerText.trim() ??
                '',
          ) ??
          0;
      final lm = _local(resp, 'getlastmodified').firstOrNull?.innerText.trim();
      DateTime modified;
      try {
        modified = lm == null ? DateTime.utc(1970) : HttpDate.parse(lm);
      } on FormatException {
        modified = DateTime.utc(1970);
      }
      out.add(
        CloudObject(name: name, path: rel, size: len, modified: modified),
      );
    }
    return out;
  }

  /// PUT with bounded retry (§6 partial-upload recovery). 5xx and wire
  /// failures back off and re-PUT; 4xx is final — wrong credentials or
  /// permissions must surface, not loop.
  Future<void> put(String relPath, Uint8List bytes) async {
    final url = _url(relPath);
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      if (attempt > 0) {
        await _sleep(Duration(milliseconds: 250 * attempt * attempt));
      }
      try {
        final r = await _send(
          'PUT',
          url,
          headers: {'Content-Type': 'application/octet-stream'},
          body: bytes,
        );
        if (r.statusCode >= 200 && r.statusCode < 300) return;
        if (r.statusCode < 500) {
          throw WebdavException('PUT', url, r.statusCode);
        }
        lastError = WebdavException('PUT', url, r.statusCode, 'server error');
      } on http.ClientException catch (e) {
        lastError = WebdavTransportException('PUT', url, e);
      }
    }
    if (lastError is Exception) throw lastError;
    throw WebdavTransportException('PUT', url, lastError ?? 'no attempt ran');
  }

  Future<Uint8List> get(String relPath) async {
    final r = await _send('GET', _url(relPath));
    if (r.statusCode != 200) {
      throw WebdavException('GET', _url(relPath), r.statusCode);
    }
    return r.bodyBytes;
  }

  /// DELETE; 404 counts as done (prune of an entry another prune got).
  Future<void> delete(String relPath) async {
    final r = await _send('DELETE', _url(relPath));
    if (r.statusCode == 204 ||
        r.statusCode == 200 ||
        r.statusCode == 205 ||
        r.statusCode == 404) {
      return;
    }
    throw WebdavException('DELETE', _url(relPath), r.statusCode);
  }

  /// The §3.2 contract in one call: upload, THEN prune from the fresh
  /// listing — delete only runs against a server that already took the
  /// new container. Returns the applied plan.
  Future<RetentionPlan> putAndPrune({
    required String folder,
    required String name,
    required Uint8List bytes,
  }) async {
    await put('$folder/$name', bytes);
    final plan = prunePlan(await list(folder));
    for (final doomed in plan.delete) {
      await delete(doomed.path);
    }
    return plan;
  }

  static String _normalizeRel(String rel) =>
      rel.endsWith('/') ? rel.substring(0, rel.length - 1) : rel;

  /// Descendant elements by LOCAL name — `d:multistatus`/`DAV:` prefixes
  /// defeat findAllElements('name'), which only matches unprefixed names.
  static Iterable<XmlElement> _local(XmlNode root, String local) => root
      .descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == local);

  /// Turn a multistatus <href> (absolute-path or full-URL form) into a
  /// base-relative path for our listing consumers.
  String _relFromHref(String href) {
    var path = href;
    if (path.contains('://')) {
      path = Uri.parse(path).path;
    } else {
      path = Uri.decodeComponent(path);
    }
    var basePath = base.path;
    if (!basePath.endsWith('/')) basePath = '$basePath/';
    var rel = path;
    if (rel.startsWith(basePath)) {
      rel = rel.substring(basePath.length);
    } else if (rel.startsWith('/')) {
      rel = rel.substring(
        1,
      ); // server rooted elsewhere; last segment still right
    }
    return _normalizeRel(rel);
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
