import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/services/media_store/icloud_media_object_store.dart';
import 'package:submersion/core/services/media_store/icloud_media_platform.dart';
import 'package:submersion/core/services/media_store/media_object_store.dart';

import 'media_object_store_contract.dart';

class _NoContainerPlatform extends DirectoryICloudMediaPlatform {
  _NoContainerPlatform(super.root);

  @override
  Future<String?> containerPath() async => null;
}

void main() {
  late Directory container;
  late Directory tmp;

  ICloudMediaObjectStore build({int? smallFileThresholdBytes}) {
    return ICloudMediaObjectStore(
      platform: DirectoryICloudMediaPlatform(container),
      smallFileThresholdBytes: smallFileThresholdBytes ?? 8 * 1024 * 1024,
    );
  }

  setUp(() async {
    container = await Directory.systemTemp.createTemp('icloud_container');
    tmp = await Directory.systemTemp.createTemp('icloud_mos_test');
  });

  tearDown(() async {
    await container.delete(recursive: true);
    await tmp.delete(recursive: true);
  });

  runMediaObjectStoreContract('ICloudMediaObjectStore', () async {
    // Fresh container per contract test.
    container = await Directory.systemTemp.createTemp('icloud_contract');
    return build();
  });

  test('large putFile lands via moveIntoContainer and the staging copy is '
      'gone', () async {
    final store = build(smallFileThresholdBytes: 1024);
    final bytes = List<int>.generate(4096, (i) => i % 251);
    final src = File('${tmp.path}/video.mp4')..writeAsBytesSync(bytes);

    final progress = <int>[];
    await store.putFile(
      'smv1/objects/aa/video.mp4',
      src,
      contentType: 'video/mp4',
      onProgress: (sent, total) => progress.add(sent),
    );

    final landed = File(
      '${container.path}/submersion-media/smv1/objects/aa/video.mp4',
    );
    expect(await landed.readAsBytes(), bytes);
    expect(
      File(
        '${container.path}/submersion-media/smv1/objects/aa/'
        'video.mp4.uploading',
      ).existsSync(),
      isFalse,
    );
    expect(progress.single, bytes.length);
    // The .uploading staging suffix never leaks into listings.
    final keys = await store.list('smv1/').map((o) => o.key).toList();
    expect(keys, ['smv1/objects/aa/video.mp4']);
  });

  test('null container path maps to a fatal MediaStoreException', () async {
    final store = ICloudMediaObjectStore(
      platform: _NoContainerPlatform(container),
    );
    final src = File('${tmp.path}/x.jpg')
      ..writeAsBytesSync(Uint8List.fromList([1]));
    await expectLater(
      store.putFile('smv1/objects/aa/x.jpg', src, contentType: 'image/jpeg'),
      throwsA(
        isA<MediaStoreException>().having(
          (e) => e.kind,
          'kind',
          MediaStoreErrorKind.fatal,
        ),
      ),
    );
  });
}
