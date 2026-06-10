import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:submersion/core/services/cloud_storage/cloud_storage_provider.dart';
import 'package:submersion/core/services/cloud_storage/s3/s3_api_client.dart';
import 'package:submersion/core/services/cloud_storage/s3/s3_config.dart';

S3Config minioConfig() => S3Config(
  endpoint: 'http://nas.local:9000',
  bucket: 'dive-sync',
  accessKeyId: 'ak',
  secretAccessKey: 'sk',
);

S3Config awsConfig() => S3Config(
  endpoint: '',
  region: 'eu-west-1',
  bucket: 'dive-sync',
  accessKeyId: 'ak',
  secretAccessKey: 'sk',
);

S3ApiClient clientWith(S3Config config, MockClient mock) => S3ApiClient(
  config,
  httpClient: mock,
  now: () => DateTime.utc(2026, 6, 9, 12),
  retryDelay: Duration.zero,
);

void main() {
  group('request shape', () {
    test(
      'path-style custom endpoint: bucket in path, port preserved',
      () async {
        late http.Request seen;
        final mock = MockClient((request) async {
          seen = request;
          return http.Response('', 200);
        });
        await clientWith(
          minioConfig(),
          mock,
        ).putObject('submersion-sync/file.json', Uint8List.fromList([1, 2]));

        expect(seen.method, 'PUT');
        expect(
          seen.url.toString(),
          'http://nas.local:9000/dive-sync/submersion-sync/file.json',
        );
        expect(seen.bodyBytes, [1, 2]);
        expect(seen.headers['authorization'], startsWith('AWS4-HMAC-SHA256 '));
        expect(seen.headers['x-amz-date'], '20260609T120000Z');
        expect(seen.headers['x-amz-content-sha256'], isNotNull);
      },
    );

    test('virtual-hosted AWS: bucket in host, regional endpoint', () async {
      late http.Request seen;
      final mock = MockClient((request) async {
        seen = request;
        return http.Response.bytes([9, 9], 200);
      });
      await clientWith(
        awsConfig(),
        mock,
      ).getObject('submersion-sync/file.json');

      expect(
        seen.url.toString(),
        'https://dive-sync.s3.eu-west-1.amazonaws.com/submersion-sync/file.json',
      );
    });

    test(
      'AWS with pathStyle forced: bucket in path on regional host',
      () async {
        late http.Request seen;
        final mock = MockClient((request) async {
          seen = request;
          return http.Response.bytes([9], 200);
        });
        final config = awsConfig().copyWith(pathStyle: true);
        await clientWith(config, mock).getObject('k.json');

        expect(
          seen.url.toString(),
          'https://s3.eu-west-1.amazonaws.com/dive-sync/k.json',
        );
      },
    );

    test('keys needing encoding sign and ship the same bytes', () async {
      late http.Request seen;
      final mock = MockClient((request) async {
        seen = request;
        return http.Response('', 200);
      });
      await clientWith(
        minioConfig(),
        mock,
      ).putObject('sub dir/submersion_sync_ā.json', Uint8List.fromList([1]));
      expect(
        seen.url.toString(),
        'http://nas.local:9000/dive-sync/sub%20dir/submersion_sync_%C4%81.json',
      );
    });
  });

  group('putObject', () {
    test('completes on 200', () async {
      final mock = MockClient((_) async => http.Response('', 200));
      await clientWith(
        minioConfig(),
        mock,
      ).putObject('k', Uint8List.fromList([1]));
    });

    test('403 throws CloudStorageException mentioning access', () async {
      final mock = MockClient((_) async => http.Response('denied', 403));
      expect(
        () => clientWith(
          minioConfig(),
          mock,
        ).putObject('k', Uint8List.fromList([1])),
        throwsA(
          isA<CloudStorageException>().having(
            (e) => e.message,
            'message',
            contains('Access denied'),
          ),
        ),
      );
    });
  });

  group('getObject', () {
    test('returns body bytes on 200', () async {
      final mock = MockClient(
        (_) async => http.Response.bytes([10, 20, 30], 200),
      );
      final bytes = await clientWith(minioConfig(), mock).getObject('k');
      expect(bytes, [10, 20, 30]);
    });

    test('404 throws CloudStorageException naming the key', () async {
      final mock = MockClient((_) async => http.Response('missing', 404));
      expect(
        () => clientWith(minioConfig(), mock).getObject('gone.json'),
        throwsA(
          isA<CloudStorageException>().having(
            (e) => e.message,
            'message',
            contains('gone.json'),
          ),
        ),
      );
    });
  });

  group('retry', () {
    test('retries once after a transport error, then succeeds', () async {
      var calls = 0;
      final mock = MockClient((_) async {
        calls++;
        if (calls == 1) throw http.ClientException('connection reset');
        return http.Response('', 200);
      });
      await clientWith(
        minioConfig(),
        mock,
      ).putObject('k', Uint8List.fromList([1]));
      expect(calls, 2);
    });

    test('retries once after a 5xx, then succeeds', () async {
      var calls = 0;
      final mock = MockClient((_) async {
        calls++;
        return http.Response('oops', calls == 1 ? 500 : 200);
      });
      await clientWith(
        minioConfig(),
        mock,
      ).putObject('k', Uint8List.fromList([1]));
      expect(calls, 2);
    });

    test(
      'persistent transport failure surfaces CloudStorageException',
      () async {
        final mock = MockClient((_) async {
          throw http.ClientException('refused');
        });
        expect(
          () => clientWith(minioConfig(), mock).getObject('k'),
          throwsA(
            isA<CloudStorageException>().having(
              (e) => e.message,
              'message',
              contains('nas.local'),
            ),
          ),
        );
      },
    );
  });

  group('headObject', () {
    test('parses key, last-modified, and size from headers', () async {
      final mock = MockClient(
        (_) async => http.Response(
          '',
          200,
          headers: {
            'last-modified': 'Wed, 03 Jun 2026 10:15:30 GMT',
            'content-length': '2048',
          },
        ),
      );
      final info = await clientWith(minioConfig(), mock).headObject('k.json');
      expect(info, isNotNull);
      expect(info!.key, 'k.json');
      expect(info.lastModified, DateTime.utc(2026, 6, 3, 10, 15, 30));
      expect(info.size, 2048);
    });

    test('returns null on 404', () async {
      final mock = MockClient((_) async => http.Response('', 404));
      expect(await clientWith(minioConfig(), mock).headObject('k'), isNull);
    });
  });

  group('deleteObject', () {
    test('204 and 404 both complete without throwing', () async {
      for (final status in [204, 404]) {
        final mock = MockClient((_) async => http.Response('', status));
        await clientWith(minioConfig(), mock).deleteObject('k');
      }
    });
  });

  group('listObjects', () {
    const pageOne = '''
<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Name>dive-sync</Name>
  <Prefix>submersion-sync/</Prefix>
  <IsTruncated>true</IsTruncated>
  <NextContinuationToken>token-1</NextContinuationToken>
  <Contents>
    <Key>submersion-sync/submersion_sync_device-a.json</Key>
    <LastModified>2026-06-01T10:00:00.000Z</LastModified>
    <Size>2048</Size>
  </Contents>
  <Contents>
    <Key>submersion-sync/submersion_sync_device-b.json</Key>
    <LastModified>2026-06-02T11:30:00.000Z</LastModified>
    <Size>4096</Size>
  </Contents>
</ListBucketResult>''';

    const pageTwo = '''
<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Name>dive-sync</Name>
  <Prefix>submersion-sync/</Prefix>
  <IsTruncated>false</IsTruncated>
  <Contents>
    <Key>submersion-sync/submersion_sync_device-c.json</Key>
    <LastModified>2026-06-03T09:00:00.000Z</LastModified>
    <Size>1024</Size>
  </Contents>
</ListBucketResult>''';

    test('follows continuation tokens across pages', () async {
      final seenUrls = <Uri>[];
      final mock = MockClient((request) async {
        seenUrls.add(request.url);
        final isSecondPage =
            request.url.queryParameters['continuation-token'] == 'token-1';
        return http.Response(isSecondPage ? pageTwo : pageOne, 200);
      });

      final objects = await clientWith(
        minioConfig(),
        mock,
      ).listObjects(prefix: 'submersion-sync/');

      expect(objects, hasLength(3));
      expect(objects[0].key, 'submersion-sync/submersion_sync_device-a.json');
      expect(objects[0].lastModified, DateTime.utc(2026, 6, 1, 10));
      expect(objects[0].size, 2048);
      expect(objects[2].key, 'submersion-sync/submersion_sync_device-c.json');

      expect(seenUrls, hasLength(2));
      expect(seenUrls[0].queryParameters['list-type'], '2');
      expect(seenUrls[0].queryParameters['prefix'], 'submersion-sync/');
      expect(seenUrls[1].queryParameters['continuation-token'], 'token-1');
    });

    test('list URL targets the bucket root, not an object', () async {
      late Uri seen;
      final mock = MockClient((request) async {
        seen = request.url;
        return http.Response(pageTwo, 200);
      });
      await clientWith(minioConfig(), mock).listObjects(prefix: 'p/');
      expect(seen.path, '/dive-sync/');
    });
  });

  group('error code mapping', () {
    test('RequestTimeTooSkewed surfaces a clock message', () async {
      const skewBody = '''
<?xml version="1.0" encoding="UTF-8"?>
<Error>
  <Code>RequestTimeTooSkewed</Code>
  <Message>The difference between the request time and the current time is too large.</Message>
</Error>''';
      final mock = MockClient((_) async => http.Response(skewBody, 403));
      expect(
        () => clientWith(minioConfig(), mock).getObject('k'),
        throwsA(
          isA<CloudStorageException>().having(
            (e) => e.message,
            'message',
            contains('clock'),
          ),
        ),
      );
    });

    test('NoSuchBucket surfaces the bucket name', () async {
      const noBucketBody = '''
<?xml version="1.0" encoding="UTF-8"?>
<Error>
  <Code>NoSuchBucket</Code>
  <Message>The specified bucket does not exist</Message>
</Error>''';
      final mock = MockClient((_) async => http.Response(noBucketBody, 404));
      expect(
        () => clientWith(minioConfig(), mock).listObjects(prefix: 'p/'),
        throwsA(
          isA<CloudStorageException>().having(
            (e) => e.message,
            'message',
            contains('dive-sync'),
          ),
        ),
      );
    });

    test('error messages never contain the secret key', () async {
      final mock = MockClient((_) async => http.Response('x', 403));
      try {
        await clientWith(minioConfig(), mock).getObject('k');
        fail('expected CloudStorageException');
      } on CloudStorageException catch (e) {
        expect(e.toString(), isNot(contains('sk')));
      }
    });
  });

  group('retry and decoding hardening', () {
    test(
      'second 5xx surfaces as CloudStorageException with the status',
      () async {
        final mock = MockClient((_) async => http.Response('oops', 503));
        expect(
          () => clientWith(minioConfig(), mock).getObject('k'),
          throwsA(
            isA<CloudStorageException>().having(
              (e) => e.message,
              'message',
              contains('503'),
            ),
          ),
        );
      },
    );

    test('5xx followed by a transport error is wrapped, not leaked', () async {
      var calls = 0;
      final mock = MockClient((_) async {
        calls++;
        if (calls == 1) return http.Response('oops', 500);
        throw http.ClientException('connection reset');
      });
      expect(
        () => clientWith(minioConfig(), mock).getObject('k'),
        throwsA(isA<CloudStorageException>()),
      );
    });

    test('TLS handshake failures are wrapped, not leaked', () async {
      final mock = MockClient((_) async {
        throw const HandshakeException('self-signed certificate');
      });
      expect(
        () => clientWith(minioConfig(), mock).getObject('k'),
        throwsA(isA<CloudStorageException>()),
      );
    });

    test('list decodes keys as UTF-8 regardless of charset header', () async {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <IsTruncated>false</IsTruncated>
  <Contents>
    <Key>submersion-sync/sync_ā.json</Key>
    <LastModified>2026-06-01T10:00:00.000Z</LastModified>
    <Size>1</Size>
  </Contents>
</ListBucketResult>''';
      final mock = MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(xml),
          200,
          headers: {'content-type': 'application/xml'},
        ),
      );
      final objects = await clientWith(
        minioConfig(),
        mock,
      ).listObjects(prefix: 'submersion-sync/');
      expect(objects.single.key, 'submersion-sync/sync_ā.json');
    });

    test(
      'IsTruncated without a token terminates with partial results',
      () async {
        const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <IsTruncated>true</IsTruncated>
  <Contents>
    <Key>p/a.json</Key>
    <LastModified>2026-06-01T10:00:00.000Z</LastModified>
    <Size>1</Size>
  </Contents>
</ListBucketResult>''';
        var calls = 0;
        final mock = MockClient((_) async {
          calls++;
          return http.Response(xml, 200);
        });
        final objects = await clientWith(
          minioConfig(),
          mock,
        ).listObjects(prefix: 'p/');
        expect(objects, hasLength(1));
        expect(calls, 1);
      },
    );

    test('4xx is never retried', () async {
      var calls = 0;
      final mock = MockClient((_) async {
        calls++;
        return http.Response('denied', 403);
      });
      await expectLater(
        clientWith(minioConfig(), mock).getObject('k'),
        throwsA(isA<CloudStorageException>()),
      );
      expect(calls, 1);
    });
  });
}
