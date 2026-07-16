import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/services/sync/changeset_log/changeset_log_layout.dart';
import 'package:submersion/core/services/sync/changeset_log/device_retirement.dart';
import 'package:submersion/core/services/sync/changeset_log/retirement_marker.dart';
import 'package:submersion/core/services/sync/changeset_log/sync_manifest.dart';
import 'package:submersion/features/dive_log/data/repositories/dive_repository_impl.dart';

import '../../../../helpers/changeset_test_helpers.dart';
import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/test_database.dart';
import '../../../../support/fake_cloud_storage_provider.dart';

void main() {
  late FakeCloudStorageProvider cloud;
  late String folder;
  const now = 2000000000000;
  const thirteenMonths = 400 * 24 * 60 * 60 * 1000;

  setUp(() async {
    await setUpTestDatabase();
    cloud = FakeCloudStorageProvider();
    folder = await cloud.getOrCreateSyncFolder();
  });
  tearDown(() => tearDownTestDatabase());

  Future<SyncManifest> agePeerManifest(String peerId, int updatedAt) async {
    final name = ChangesetLogLayout.manifestName(peerId);
    final fresh = SyncManifest.fromBytes(
      await cloud.downloadFile('$folder/$name'),
    );
    final aged = SyncManifest(
      deviceId: fresh.deviceId,
      provider: fresh.provider,
      baseSeq: fresh.baseSeq,
      basePartCount: fresh.basePartCount,
      baseBytes: fresh.baseBytes,
      baseChecksum: fresh.baseChecksum,
      basePartChecksums: fresh.basePartChecksums,
      headSeq: fresh.headSeq,
      publishedHlcHigh: fresh.publishedHlcHigh,
      updatedAt: updatedAt,
    );
    await cloud.uploadFile(aged.toBytes(), name, folderId: folder);
    return aged;
  }

  Future<List<String>> names() async {
    final files = await cloud.listFiles(
      folderId: folder,
      namePattern: ChangesetLogLayout.prefix,
    );
    return files.map((f) => f.name).toList();
  }

  test('retires a 13-month-idle peer: marker first, files deleted', () async {
    await DiveRepository().createDive(
      createTestDiveWithBottomTime(id: 'p1', diveNumber: 1),
    );
    await seedPeerLog(cloud, 'peer-old');
    final aged = await agePeerManifest('peer-old', now - thirteenMonths);

    final retired = await DeviceRetirement().sweep(
      provider: cloud,
      folderId: folder,
      selfDeviceId: 'self',
      peerManifests: [aged],
      alreadyRetired: const {},
      retiredPeerHasFiles: false,
      nowMillis: now,
    );

    expect(retired, 1);
    final ns = await names();
    expect(ns, contains(ChangesetLogLayout.retiredMarkerName('peer-old')));
    expect(
      ns
          .where((n) => !ChangesetLogLayout.isRetiredMarker(n))
          .where((n) => ChangesetLogLayout.deviceIdOf(n) == 'peer-old'),
      isEmpty,
      reason: 'manifest, base parts, and changesets must be deleted',
    );
    final marker = RetirementMarker.fromBytes(
      await cloud.downloadFile(
        '$folder/${ChangesetLogLayout.retiredMarkerName('peer-old')}',
      ),
    );
    expect(marker.deviceId, 'peer-old');
    expect(marker.retiredAt, now);
  });

  test('never retires a fresh peer or self', () async {
    await DiveRepository().createDive(
      createTestDiveWithBottomTime(id: 'p1', diveNumber: 1),
    );
    await seedPeerLog(cloud, 'peer-fresh');
    final fresh = await agePeerManifest('peer-fresh', now - 1000);
    const selfAged = SyncManifest(
      deviceId: 'self',
      provider: 'fake',
      headSeq: 1,
      updatedAt: now - thirteenMonths,
    );

    final retired = await DeviceRetirement().sweep(
      provider: cloud,
      folderId: folder,
      selfDeviceId: 'self',
      peerManifests: [fresh, selfAged],
      alreadyRetired: const {},
      retiredPeerHasFiles: false,
      nowMillis: now,
    );

    expect(retired, 0);
    final ns = await names();
    expect(
      ns,
      isNot(contains(ChangesetLogLayout.retiredMarkerName('peer-fresh'))),
    );
    expect(ns, isNot(contains(ChangesetLogLayout.retiredMarkerName('self'))));
  });

  test(
    'retries deletion for an already-marked peer with leftover files',
    () async {
      await DiveRepository().createDive(
        createTestDiveWithBottomTime(id: 'p1', diveNumber: 1),
      );
      await seedPeerLog(cloud, 'peer-partial');
      await cloud.uploadFile(
        const RetirementMarker(
          deviceId: 'peer-partial',
          retiredAt: 1,
        ).toBytes(),
        ChangesetLogLayout.retiredMarkerName('peer-partial'),
        folderId: folder,
      );

      final retired = await DeviceRetirement().sweep(
        provider: cloud,
        folderId: folder,
        selfDeviceId: 'self',
        peerManifests: const [],
        alreadyRetired: const {'peer-partial'},
        retiredPeerHasFiles: true,
        nowMillis: now,
      );

      expect(retired, 0);
      final ns = await names();
      expect(
        ns,
        contains(ChangesetLogLayout.retiredMarkerName('peer-partial')),
        reason: 'the marker must survive the sweep',
      );
      expect(
        ns
            .where((n) => !ChangesetLogLayout.isRetiredMarker(n))
            .where((n) => ChangesetLogLayout.deviceIdOf(n) == 'peer-partial'),
        isEmpty,
        reason: 'leftover data files must be swept',
      );
    },
  );
}
