import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:submersion/core/data/repositories/sync_repository.dart';
import 'package:submersion/core/services/cloud_storage/cloud_storage_provider.dart';
import 'package:submersion/core/services/database_service.dart';
import 'package:submersion/core/services/sync/library_epoch.dart';
import 'package:submersion/core/services/sync/library_epoch_store.dart';
import 'package:submersion/core/services/sync/sync_data_serializer.dart';
import 'package:submersion/core/services/sync/sync_service.dart';

import '../../../helpers/fake_cloud_storage_provider.dart';
import '../../../helpers/test_database.dart';

/// Coverage for the library epoch protocol on SyncService (restore Replace
/// mode): marker IO, the performSync gate, replace execution, and adoption.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeCloudStorageProvider cloud;
  late LibraryEpochStore epochStore;

  setUp(() async {
    await setUpTestDatabase();
    SharedPreferences.setMockInitialValues({});
    epochStore = LibraryEpochStore(await SharedPreferences.getInstance());
    cloud = FakeCloudStorageProvider();
  });

  tearDown(() => DatabaseService.instance.resetForTesting());

  SyncService buildService() => SyncService(
    syncRepository: SyncRepository(),
    serializer: SyncDataSerializer(),
    cloudProvider: cloud,
    epochStore: epochStore,
  );

  /// Seed a peer's sync file in the cloud: a valid checksummed payload (it
  /// exports the current local test DB) under [peerDeviceId], optionally
  /// stamped with [epochId].
  Future<void> seedPeerFile({
    required String peerDeviceId,
    String? epochId,
  }) async {
    final serializer = SyncDataSerializer();
    final payload = await serializer.exportData(
      deviceId: peerDeviceId,
      since: null,
      lastSyncTimestamp: null,
      deletions: const [],
      uploadNonce: null,
      epochId: epochId,
    );
    final json = serializer.serializePayload(payload);
    await cloud.uploadFile(
      Uint8List.fromList(utf8.encode(json)),
      '${CloudStorageProviderMixin.syncFilePrefix}$peerDeviceId'
      '${CloudStorageProviderMixin.syncFileExtension}',
    );
  }

  group('marker IO', () {
    const marker = LibraryEpochMarker(
      epochId: 'e1',
      replacedAt: 1,
      deviceId: 'd1',
    );

    test('read returns null when no marker exists', () async {
      final service = buildService();
      expect(await service.readLibraryEpochMarker(cloud), isNull);
    });

    test('write then read round-trips', () async {
      final service = buildService();
      await service.writeLibraryEpochMarker(cloud, marker);
      final read = await service.readLibraryEpochMarker(cloud);
      expect(read?.epochId, 'e1');
    });

    test('marker file is invisible to sync-file discovery', () async {
      final service = buildService();
      await service.writeLibraryEpochMarker(cloud, marker);
      final files = await cloud.listFiles(
        namePattern: CloudStorageProviderMixin.syncFileStem,
      );
      expect(files.where((f) => f.name == libraryEpochFileName), isEmpty);
    });

    test('corrupt marker throws (read failure, not absence)', () async {
      await cloud.uploadFile(
        Uint8List.fromList(utf8.encode('not json')),
        libraryEpochFileName,
      );
      final service = buildService();
      expect(
        () => service.readLibraryEpochMarker(cloud),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('executeLibraryReplace', () {
    const marker = LibraryEpochMarker(
      epochId: 'new-epoch',
      replacedAt: 1,
      deviceId: 'replacer',
    );

    test('wipes sync files, writes marker before wipe, uploads stamped file, '
        'commits epoch', () async {
      // Seed: one peer file and one legacy shared file in the cloud.
      await cloud.uploadFile(
        Uint8List.fromList(utf8.encode('{"version":1}')),
        '${CloudStorageProviderMixin.syncFilePrefix}peer-1'
        '${CloudStorageProviderMixin.syncFileExtension}',
      );
      await cloud.uploadFile(
        Uint8List.fromList(utf8.encode('{"version":1}')),
        CloudStorageProviderMixin.canonicalSyncFileName,
      );
      await epochStore.setPendingReplace(marker);
      cloud.operationLog.clear();

      final service = buildService();
      final result = await service.executeLibraryReplace(marker);

      expect(result.isSuccess, isTrue);
      // Marker upload happens before any sync-file delete.
      final markerIdx = cloud.operationLog.indexWhere(
        (op) => op == 'upload:$libraryEpochFileName',
      );
      final firstDeleteIdx = cloud.operationLog.indexWhere(
        (op) => op.startsWith('delete:'),
      );
      expect(markerIdx, isNonNegative);
      expect(firstDeleteIdx, isNonNegative);
      expect(markerIdx, lessThan(firstDeleteIdx));

      // Peer and legacy files are gone; our stamped file exists.
      final files = await cloud.listFiles(
        namePattern: CloudStorageProviderMixin.syncFileStem,
      );
      final deviceId = await SyncRepository().getDeviceId();
      expect(files.map((f) => f.name), [
        '${CloudStorageProviderMixin.syncFilePrefix}$deviceId'
            '${CloudStorageProviderMixin.syncFileExtension}',
      ]);
      final uploaded = SyncDataSerializer().deserializePayload(
        utf8.decode(cloud.syncFileBytes()!),
      );
      expect(uploaded.epochId, 'new-epoch');

      // Epoch committed to both anchors; intent cleared; lastSync set.
      expect(await SyncRepository().getLastAcceptedEpochId(), 'new-epoch');
      expect(epochStore.lastAcceptedEpochId, 'new-epoch');
      expect(epochStore.pendingReplace, isNull);
      expect(await SyncRepository().getLastSyncTime(), isNotNull);
    });

    test('upload failure keeps the pending intent for retry', () async {
      await epochStore.setPendingReplace(marker);
      cloud.failUploads = true;

      final service = buildService();
      final result = await service.executeLibraryReplace(marker);

      expect(result.isSuccess, isFalse);
      expect(epochStore.pendingReplace?.epochId, 'new-epoch');
      expect(await SyncRepository().getLastAcceptedEpochId(), isNull);
    });
  });

  group('performSync epoch gating', () {
    const marker = LibraryEpochMarker(
      epochId: 'e1',
      replacedAt: 1,
      deviceId: 'replacer',
    );

    test('pending intent executes the replace instead of merging', () async {
      await seedPeerFile(peerDeviceId: 'peer-1');
      await epochStore.setPendingReplace(marker);

      final result = await buildService().performSync();

      expect(result.isSuccess, isTrue);
      expect(epochStore.pendingReplace, isNull);
      expect(await SyncRepository().getLastAcceptedEpochId(), 'e1');
      // The peer file was wiped, not merged.
      final files = await cloud.listFiles(
        namePattern: CloudStorageProviderMixin.syncFileStem,
      );
      expect(files.any((f) => f.name.contains('peer-1')), isFalse);
    });

    test(
      'no marker + no accepted epoch behaves as legacy (normal sync)',
      () async {
        final result = await buildService().performSync();
        expect(result.isSuccess, isTrue);
        expect(result.status, isNot(SyncResultStatus.awaitingAdoption));
      },
    );

    test(
      'marker matching accepted epoch proceeds and filters stale files',
      () async {
        final service = buildService();
        await service.writeLibraryEpochMarker(cloud, marker);
        await SyncRepository().setLastAcceptedEpochId('e1');
        await epochStore.setLastAccepted(marker);
        await seedPeerFile(peerDeviceId: 'stale-peer'); // unstamped = stale
        await seedPeerFile(peerDeviceId: 'fresh-peer', epochId: 'e1');

        final result = await service.performSync();

        expect(result.isSuccess, isTrue);
        // Stale file was ignored and opportunistically deleted.
        final files = await cloud.listFiles(
          namePattern: CloudStorageProviderMixin.syncFileStem,
        );
        expect(files.any((f) => f.name.contains('stale-peer')), isFalse);
        expect(files.any((f) => f.name.contains('fresh-peer')), isTrue);
      },
    );

    test('marker mismatch halts before merge or upload', () async {
      final service = buildService();
      await service.writeLibraryEpochMarker(cloud, marker);
      // This device never accepted e1.
      await seedPeerFile(peerDeviceId: 'peer-1', epochId: 'e1');
      cloud.operationLog.clear();

      final result = await service.performSync();

      expect(result.status, SyncResultStatus.awaitingAdoption);
      expect(result.replaceMarker?.epochId, 'e1');
      // No upload of our own file happened.
      expect(
        cloud.operationLog.where((op) => op.startsWith('upload:')),
        isEmpty,
      );
    });

    test('missing marker with accepted epoch self-heals the marker', () async {
      await SyncRepository().setLastAcceptedEpochId('e1');
      await epochStore.setLastAccepted(marker);

      final service = buildService();
      final result = await service.performSync();

      expect(result.isSuccess, isTrue);
      expect((await service.readLibraryEpochMarker(cloud))?.epochId, 'e1');
    });

    test('unreadable marker fails the sync closed', () async {
      await cloud.uploadFile(
        Uint8List.fromList(utf8.encode('not json')),
        libraryEpochFileName,
      );
      final result = await buildService().performSync();
      expect(result.status, SyncResultStatus.error);
    });
  });
}
