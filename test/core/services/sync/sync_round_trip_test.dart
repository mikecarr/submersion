import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/data/repositories/sync_repository.dart';
import 'package:submersion/core/services/database_service.dart';
import 'package:submersion/core/services/sync/sync_data_serializer.dart';
import 'package:submersion/core/services/sync/sync_service.dart';
import 'package:submersion/features/dive_log/data/repositories/dive_repository_impl.dart';

import '../../../helpers/fake_cloud_storage_provider.dart';
import '../../../helpers/test_database.dart';
import '../../../helpers/mock_providers.dart';

void main() {
  group('Sync end-to-end round-trip (fake provider)', () {
    late FakeCloudStorageProvider cloud;

    setUp(() async {
      await setUpTestDatabase();
      cloud = FakeCloudStorageProvider();
    });

    tearDown(() {
      DatabaseService.instance.resetForTesting();
    });

    SyncService buildService() => SyncService(
      syncRepository: SyncRepository(),
      serializer: SyncDataSerializer(),
      cloudProvider: cloud,
    );

    test('a dive created on "device A" is restored on "device B"', () async {
      final diveRepo = DiveRepository();

      // Device A: seed and push.
      await diveRepo.createDive(
        createTestDiveWithBottomTime(id: 'dive-xfer-1', diveNumber: 11),
      );
      final pushResult = await buildService().performSync();
      expect(
        pushResult.isSuccess,
        isTrue,
        reason:
            'device A push should succeed; got ${pushResult.status} '
            '(${pushResult.message})',
      );
      expect(
        cloud.bytesOf('submersion_sync.json'),
        isNotNull,
        reason: 'the canonical sync file should exist in the cloud after push',
      );
      // Export side is healthy: device A's upload must contain the dive.
      final afterPush = SyncDataSerializer().deserializePayload(
        utf8.decode(await cloud.downloadFile('submersion_sync.json')),
      );
      expect(
        afterPush.data.dives.length,
        1,
        reason: 'device A export uploaded the dive (export side is healthy)',
      );

      // Impersonate a FRESH device B sharing the same cloud: remove the dive
      // locally first (this logs a deletion), THEN reset sync state, which
      // clears the deletion log and the last-sync timestamp. The result is a
      // device that looks like it never had the dive (not one that deleted it).
      await diveRepo.deleteDive('dive-xfer-1');
      await SyncRepository().resetSyncState();
      expect(
        await diveRepo.getDiveById('dive-xfer-1'),
        isNull,
        reason: 'precondition: dive is gone locally before the pull',
      );

      // Device B: pull.
      final pullResult = await buildService().performSync();
      expect(
        pullResult.isSuccess,
        isTrue,
        reason:
            'device B pull should succeed; got ${pullResult.status} '
            '(${pullResult.message})',
      );

      // The decisive assertion. Regression test for the cross-device sync
      // no-op: the non-nullable v1.5 field `isPlanned` was missing from the
      // dive export, so Dive.fromJson threw on every receiving device and
      // _mergeEntity masked it as a "conflict" -- so nothing ever synced.
      // Fixed by exporting isPlanned. See
      // docs/superpowers/findings/2026-06-02-icloud-sync-diagnosis.md.
      final restored = await diveRepo.getDiveById('dive-xfer-1');
      expect(
        restored,
        isNotNull,
        reason: 'THE BUG: dive did not propagate A -> B through the round-trip',
      );
    });

    test('dive field values survive A -> B, not just the row', () async {
      final diveRepo = DiveRepository();
      await diveRepo.createDive(
        createTestDiveWithBottomTime(
          id: 'dive-fields-1',
          diveNumber: 22,
          bottomTime: const Duration(minutes: 45),
          maxDepth: 30.5,
          waterTemp: 19.0,
        ),
      );
      await buildService().performSync(); // device A push

      await diveRepo.deleteDive('dive-fields-1');
      await SyncRepository().resetSyncState();
      await buildService().performSync(); // device B pull

      final restored = await diveRepo.getDiveById('dive-fields-1');
      expect(restored, isNotNull);
      expect(
        restored!.bottomTime,
        const Duration(minutes: 45),
        reason: 'bottomTime must survive sync (was dropped via a key mismatch)',
      );
      expect(restored.maxDepth, 30.5);
      expect(restored.waterTemp, 19.0);
    });

    // Verifies the mass toJson() export conversion works for a non-dive entity.
    test('a dive site round-trips A -> B with its fields', () async {
      final serializer = SyncDataSerializer();
      final repo = SyncRepository();

      // Seed a site on "device A" via the import path (no companion needed).
      await serializer.upsertRecord('diveSites', {
        'id': 'site-rt-1',
        'name': 'Blue Hole',
        'description': 'A nice wall dive',
        'notes': '',
        'isShared': false,
        'createdAt': 1000,
        'updatedAt': 1000,
      });
      await buildService().performSync(); // push

      // Impersonate a fresh device B.
      await serializer.deleteRecord('diveSites', 'site-rt-1');
      await repo.resetSyncState();
      expect(await serializer.fetchRecord('diveSites', 'site-rt-1'), isNull);

      await buildService().performSync(); // pull

      final restored = await serializer.fetchRecord('diveSites', 'site-rt-1');
      expect(
        restored,
        isNotNull,
        reason: 'dive site should round-trip A -> B via toJson export',
      );
      expect(restored!['name'], 'Blue Hole');
    });

    // Media was broken too: its custom export dropped 5 non-nullable fields.
    test('media metadata round-trips A -> B (toJson export)', () async {
      final serializer = SyncDataSerializer();
      final repo = SyncRepository();

      await serializer.upsertRecord('media', {
        'id': 'media-rt-1',
        'filePath': '/photos/reef.jpg',
        'fileType': 'image',
        'caption': 'Reef shark',
        'isFavorite': false,
        'isOrphaned': false,
        'sourceType': 'local',
        'createdAt': 1000,
        'updatedAt': 1000,
      });
      await buildService().performSync(); // push

      await serializer.deleteRecord('media', 'media-rt-1');
      await repo.resetSyncState();
      await buildService().performSync(); // pull

      final restored = await serializer.fetchRecord('media', 'media-rt-1');
      expect(
        restored,
        isNotNull,
        reason: 'media should round-trip A -> B via toJson export',
      );
      expect(restored!['caption'], 'Reef shark');
    });
  });
}
