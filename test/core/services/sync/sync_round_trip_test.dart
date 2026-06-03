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

      // The decisive assertion. This currently FAILS: on a receiving device,
      // _mergeEntity catches an exception thrown while applying the incoming
      // dive and relabels it as a "conflict" (pull reports hasConflicts with
      // conflictsFound == 1), so the record never upserts. See the Phase 0
      // findings doc. Expected to pass once the merge-apply defect is fixed.
      final restored = await diveRepo.getDiveById('dive-xfer-1');
      expect(
        restored,
        isNotNull,
        reason: 'THE BUG: dive did not propagate A -> B through the round-trip',
      );
    });
  });
}
