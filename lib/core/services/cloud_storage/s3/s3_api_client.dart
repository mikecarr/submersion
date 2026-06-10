import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'package:submersion/core/services/cloud_storage/cloud_storage_provider.dart';
import 'package:submersion/core/services/cloud_storage/s3/s3_config.dart';
import 'package:submersion/core/services/cloud_storage/s3/sigv4_signer.dart';

/// Listing entry returned by [S3ApiClient.listObjects].
class S3ObjectInfo {
  final String key;
  final DateTime lastModified;
  final int? size;

  const S3ObjectInfo({
    required this.key,
    required this.lastModified,
    this.size,
  });
}

/// Minimal S3 REST client: the five operations the sync backend needs,
/// signed with SigV4. Throws [CloudStorageException] for every failure so
/// callers never see raw HTTP details. The secret key and Authorization
/// header are never logged or embedded in error messages.
class S3ApiClient {
  S3ApiClient(
    this._config, {
    http.Client? httpClient,
    DateTime Function()? now,
    Duration retryDelay = const Duration(milliseconds: 500),
  }) : _http = httpClient ?? http.Client(),
       _now = now ?? DateTime.now,
       _retryDelay = retryDelay;

  final S3Config _config;
  final http.Client _http;
  final DateTime Function() _now;
  final Duration _retryDelay;

  Future<void> putObject(String key, Uint8List bytes) async {
    final response = await _sendWithRetry('PUT', key, body: bytes);
    if (response.statusCode != 200) _throwFor('upload', key, response);
  }

  Future<Uint8List> getObject(String key) async {
    final response = await _sendWithRetry('GET', key);
    if (response.statusCode == 200) return response.bodyBytes;
    if (response.statusCode == 404) {
      throw CloudStorageException('File not found in S3: $key');
    }
    _throwFor('download', key, response);
  }

  Future<S3ObjectInfo?> headObject(String key) async {
    final response = await _sendWithRetry('HEAD', key);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) _throwFor('inspect', key, response);
    final lastModifiedHeader = response.headers['last-modified'];
    final contentLength = response.headers['content-length'];
    return S3ObjectInfo(
      key: key,
      lastModified: lastModifiedHeader != null
          ? HttpDate.parse(lastModifiedHeader)
          : _now().toUtc(),
      size: contentLength != null ? int.tryParse(contentLength) : null,
    );
  }

  Future<void> deleteObject(String key) async {
    final response = await _sendWithRetry('DELETE', key);
    // 404 is success for an idempotent delete; S3 itself returns 204 even
    // for keys that never existed, but some compatible servers 404.
    const okStatuses = {200, 204, 404};
    if (!okStatuses.contains(response.statusCode)) {
      _throwFor('delete', key, response);
    }
  }

  Future<List<S3ObjectInfo>> listObjects({String prefix = ''}) async {
    final results = <S3ObjectInfo>[];
    String? continuationToken;
    do {
      final response = await _sendWithRetry(
        'GET',
        '',
        queryParams: {
          'list-type': '2',
          if (prefix.isNotEmpty) 'prefix': prefix,
          'continuation-token': ?continuationToken,
        },
      );
      if (response.statusCode != 200) _throwFor('list', prefix, response);

      final document = XmlDocument.parse(utf8.decode(response.bodyBytes));
      for (final contents in document.findAllElements('Contents')) {
        final key = contents.getElement('Key')?.innerText;
        final lastModified = contents.getElement('LastModified')?.innerText;
        if (key == null || lastModified == null) continue;
        results.add(
          S3ObjectInfo(
            key: key,
            lastModified: DateTime.parse(lastModified),
            size: int.tryParse(contents.getElement('Size')?.innerText ?? ''),
          ),
        );
      }
      final truncated =
          document.findAllElements('IsTruncated').firstOrNull?.innerText ==
          'true';
      continuationToken = truncated
          ? document
                .findAllElements('NextContinuationToken')
                .firstOrNull
                ?.innerText
          : null;
    } while (continuationToken != null);
    return results;
  }

  /// Closes the underlying HTTP client (including an injected one).
  void close() => _http.close();

  /// Scheme/host/port/path for [key], honoring path-style vs virtual-hosted
  /// addressing. The path comes back already SigV4-encoded so the signed
  /// bytes and the wire bytes cannot diverge.
  ({String scheme, String host, int? port, String path}) _target(String key) {
    final String scheme;
    final String host;
    int? port;
    if (_config.isAws) {
      scheme = 'https';
      host = _config.pathStyle
          ? 's3.${_config.region}.amazonaws.com'
          : '${_config.bucket}.s3.${_config.region}.amazonaws.com';
    } else {
      final endpointUri = Uri.parse(_config.endpoint);
      scheme = endpointUri.scheme;
      host = _config.pathStyle
          ? endpointUri.host
          : '${_config.bucket}.${endpointUri.host}';
      if (endpointUri.hasPort) port = endpointUri.port;
    }
    final encodedKey = SigV4Signer.uriEncode(key, encodeSlash: false);
    final path = _config.pathStyle
        ? '/${_config.bucket}${encodedKey.isEmpty ? '/' : '/$encodedKey'}'
        : '/$encodedKey';
    return (scheme: scheme, host: host, port: port, path: path);
  }

  Future<http.Response> _sendWithRetry(
    String method,
    String key, {
    Map<String, String> queryParams = const {},
    Uint8List? body,
  }) async {
    try {
      final response = await _send(
        method,
        key,
        queryParams: queryParams,
        body: body,
      );
      if (response.statusCode < 500) return response;
    } on http.ClientException {
      // Transport failure; retry once below.
    } on IOException {
      // Socket or TLS failure; retry once below.
    } on TimeoutException {
      // Timed out; retry once below.
    }
    return _retry(method, key, queryParams, body);
  }

  Future<http.Response> _retry(
    String method,
    String key,
    Map<String, String> queryParams,
    Uint8List? body,
  ) async {
    await Future<void>.delayed(_retryDelay);
    try {
      return await _send(method, key, queryParams: queryParams, body: body);
    } on Exception catch (e) {
      throw CloudStorageException(
        'Could not reach S3 endpoint ${_config.displayHost}',
        e,
      );
    }
  }

  Future<http.Response> _send(
    String method,
    String key, {
    Map<String, String> queryParams = const {},
    Uint8List? body,
  }) async {
    final target = _target(key);
    final authority = target.port == null
        ? target.host
        : '${target.host}:${target.port}';
    final canonicalQuery = SigV4Signer.canonicalQueryString(queryParams);
    final uri = Uri.parse(
      '${target.scheme}://$authority${target.path}'
      '${canonicalQuery.isEmpty ? '' : '?$canonicalQuery'}',
    );

    final payload = body ?? Uint8List(0);
    final headers = SigV4Signer.sign(
      method: method,
      host: authority,
      canonicalUri: target.path,
      queryParams: queryParams,
      payload: payload,
      accessKeyId: _config.accessKeyId,
      secretAccessKey: _config.secretAccessKey,
      region: _config.region,
      requestTime: _now(),
    );
    // The http client derives Host from the URL; it must not be set manually.
    headers.remove('host');

    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) request.bodyBytes = body;
    return http.Response.fromStream(await _http.send(request));
  }

  Never _throwFor(String operation, String key, http.Response response) {
    final errorCode = _xmlErrorCode(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    if (response.statusCode == 403) {
      if (errorCode == 'RequestTimeTooSkewed') {
        throw const CloudStorageException(
          'S3 rejected the request time. The device clock is more than '
          '15 minutes off; correct the system time and try again.',
        );
      }
      throw const CloudStorageException(
        'Access denied. Check the access key, secret key, and bucket '
        'permissions.',
      );
    }
    if (response.statusCode == 404 && errorCode == 'NoSuchBucket') {
      throw CloudStorageException('Bucket "${_config.bucket}" not found');
    }
    throw CloudStorageException(
      'S3 $operation failed for "$key" (HTTP ${response.statusCode})',
    );
  }

  String? _xmlErrorCode(String body) {
    if (body.isEmpty) return null;
    try {
      return XmlDocument.parse(
        body,
      ).findAllElements('Code').firstOrNull?.innerText;
    } on XmlException {
      return null;
    }
  }
}
