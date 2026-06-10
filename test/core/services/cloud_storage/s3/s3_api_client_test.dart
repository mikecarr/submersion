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
}
