import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/data/repositories/sync_repository.dart';
import 'package:submersion/core/services/database_service.dart';
import 'package:submersion/core/services/sync/sync_data_serializer.dart';
import 'package:submersion/core/services/sync/sync_service.dart';

import '../../../helpers/fake_cloud_storage_provider.dart';
import '../../../helpers/test_database.dart';

/// Regression tests for the per-device "active diver" pointer firing a sync
/// conflict on every two-device exchange.
///
/// Background: at first launch each device auto-creates an owner diver with a
/// fresh UUID and persists the pointer in `settings['active_diver_id']`. The
/// settings table participates in sync; the merge key is the settings `key`
/// column, so two devices that both wrote `active_diver_id` (with their own
/// local UUID) collide on the same key with different values and the sync
/// pipeline correctly flags a conflict.
///
/// The fix is to treat `active_diver_id` as device-local: omit it from the
/// exported payload entirely. The diver *rows* still sync (different IDs, no
/// row-level conflict); only the per-device pointer stays device-local.
void main() {
  group('Sync excludes device-local settings keys', () {
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

    test(
      'active_diver_id is not present in the synced settings payload',
      () async {
        final serializer = SyncDataSerializer();

        await serializer.upsertRecord('settings', {
          'key': 'active_diver_id',
          'value': 'diver-A-uuid',
          'updatedAt': 1000,
        });

        // Seed a second, non-device-local setting so the test also proves the
        // filter is targeted, not a blanket "drop all settings" change.
        await serializer.upsertRecord('settings', {
          'key': 'units_system',
          'value': 'metric',
          'updatedAt': 1000,
        });

        await buildService().performSync();

        final payload = serializer.deserializePayload(
          utf8.decode(await cloud.downloadFile('submersion_sync.json')),
        );
        final exportedKeys = payload.data.settings.map((s) => s['key']).toSet();

        expect(
          exportedKeys,
          contains('units_system'),
          reason: 'genuine app-wide settings must still sync',
        );
        expect(
          exportedKeys,
          isNot(contains('active_diver_id')),
          reason:
              'active_diver_id is device-local; including it in the payload '
              'causes a settings conflict on every two-device exchange',
        );
      },
    );
  });
}
