import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/services/database_service.dart';
import 'package:submersion/core/services/sync/sync_data_serializer.dart';

import '../../../helpers/test_database.dart';

/// Sync replication for `dive_roles` (per-dive role vocabulary, #551/#547).
///
/// Like `dive_types`, this is reference data with seeded built-ins: only
/// custom rows sync (built-ins are re-seeded identically on every device),
/// and adopt/wipe flows must never remove the built-ins.
void main() {
  group('dive_roles sync (#551)', () {
    setUp(() async {
      await setUpTestDatabase();
    });

    tearDown(() async {
      await tearDownTestDatabase();
    });

    String hlcAt(int physical, String node) =>
        '${physical.toString().padLeft(15, '0')}:000000:$node';

    Map<String, dynamic> diveRoleRow(
      String id, {
      required String hlc,
      bool isBuiltIn = false,
      String name = 'Hekkensluiter',
      String? diverId,
    }) => {
      'id': id,
      'diverId': diverId,
      'name': name,
      'isBuiltIn': isBuiltIn,
      'sortOrder': 20,
      'createdAt': 1000,
      'updatedAt': 1000,
      'hlc': hlc,
    };

    test('export includes a custom dive_roles row', () async {
      final serializer = SyncDataSerializer();
      await serializer.upsertRecord(
        'diveRoles',
        diveRoleRow('role-1', hlc: hlcAt(1000, 'dev-a')),
      );

      final payload = await serializer.exportData(
        deviceId: 'dev-a',
        deletions: const [],
      );

      final ids = payload.data.diveRoles.map((r) => r['id']).toSet();
      expect(
        ids,
        contains('role-1'),
        reason: 'a custom dive_roles row must appear in the exported payload',
      );
    });

    test('export skips built-in dive roles', () async {
      final serializer = SyncDataSerializer();
      final payload = await serializer.exportData(
        deviceId: 'dev-a',
        deletions: const [],
      );
      expect(
        payload.data.diveRoles,
        isEmpty,
        reason: 'the 9 seeded built-ins must not sync',
      );
    });

    test(
      'incremental export: only rows with hlc > watermark are included',
      () async {
        final serializer = SyncDataSerializer();
        await serializer.upsertRecord(
          'diveRoles',
          diveRoleRow('role-old', hlc: hlcAt(1000, 'dev-a')),
        );
        await serializer.upsertRecord(
          'diveRoles',
          diveRoleRow('role-new', hlc: hlcAt(9000, 'dev-a')),
        );

        final changeset = await serializer.exportChangeset(
          deviceId: 'dev-a',
          hlcWatermark: hlcAt(5000, 'dev-a'),
          deletions: const [],
        );

        final ids = changeset.data.diveRoles.map((r) => r['id']).toSet();
        expect(ids, contains('role-new'));
        expect(ids, isNot(contains('role-old')));
      },
    );

    test('deleteAllRecords preserves built-in dive roles', () async {
      final serializer = SyncDataSerializer();
      await serializer.upsertRecord(
        'diveRoles',
        diveRoleRow('role-1', hlc: hlcAt(1000, 'dev-a')),
      );

      await serializer.deleteAllRecords('diveRoles');

      final db = DatabaseService.instance.database;
      final rows = await db.customSelect('SELECT id FROM dive_roles').get();
      final ids = rows.map((r) => r.read<String>('id')).toSet();
      expect(ids, isNot(contains('role-1')));
      expect(ids.length, 9, reason: 'built-ins survive an adopt wipe');
    });

    test('per-record plumbing: fetchRecord, recordIdsFor, deleteRecord, '
        'and SyncData.fromJson all handle diveRoles', () async {
      final serializer = SyncDataSerializer();
      await serializer.upsertRecord(
        'diveRoles',
        diveRoleRow('role-1', hlc: hlcAt(1000, 'dev-a')),
      );

      final fetched = await serializer.fetchRecord('diveRoles', 'role-1');
      expect(fetched, isNotNull);
      expect(fetched!['name'], 'Hekkensluiter');

      final missing = await serializer.fetchRecord('diveRoles', 'nope');
      expect(missing, isNull);

      // recordIdsFor enumerates every local row (built-ins included); the
      // custom row must be among them.
      final ids = await serializer.recordIdsFor('diveRoles');
      expect(ids, contains('role-1'));

      final payload = await serializer.exportData(
        deviceId: 'dev-a',
        deletions: const [],
      );
      final rehydrated = SyncData.fromJson(payload.data.toJson());
      expect(rehydrated.diveRoles.map((r) => r['id']), contains('role-1'));

      // Tombstone application path.
      await serializer.deleteRecord('diveRoles', 'role-1');
      expect(
        await serializer.recordIdsFor('diveRoles'),
        isNot(contains('role-1')),
      );
    });
  });
}
