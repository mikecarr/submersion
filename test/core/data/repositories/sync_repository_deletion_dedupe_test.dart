import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/data/repositories/sync_repository.dart';
import 'package:submersion/core/services/database_service.dart';

import '../../../helpers/test_database.dart';

void main() {
  setUp(() async => setUpTestDatabase());
  tearDown(() => tearDownTestDatabase());

  test(
    'logDeletion upserts: one tombstone per (entityType, recordId), newest wins',
    () async {
      final repo = SyncRepository();
      await repo.logDeletion(
        entityType: 'dives',
        recordId: 'd1',
        deletedAt: 1000,
      );
      await repo.logDeletion(
        entityType: 'dives',
        recordId: 'd1',
        deletedAt: 2000,
      );
      await repo.logDeletion(
        entityType: 'dives',
        recordId: 'd2',
        deletedAt: 1500,
      );

      final all = await repo.getAllDeletions();
      expect(all, hasLength(2));
      final d1 = all.singleWhere((d) => d.recordId == 'd1');
      expect(d1.deletedAt, 2000);
    },
  );

  test(
    'ensureDeletionLogIndex collapses pre-existing duplicates, newest wins',
    () async {
      final db = DatabaseService.instance.database;
      // Simulate a pre-v113 database: drop the index, insert raw duplicates.
      await db.customStatement(
        'DROP INDEX IF EXISTS idx_deletion_log_entity_record',
      );
      await db.customStatement(
        "INSERT INTO deletion_log (id, entity_type, record_id, deleted_at, hlc) "
        "VALUES ('a', 'dives', 'dup', 1000, NULL)",
      );
      await db.customStatement(
        "INSERT INTO deletion_log (id, entity_type, record_id, deleted_at, hlc) "
        "VALUES ('b', 'dives', 'dup', 3000, NULL)",
      );
      await db.customStatement(
        "INSERT INTO deletion_log (id, entity_type, record_id, deleted_at, hlc) "
        "VALUES ('c', 'dives', 'dup', 2000, NULL)",
      );

      await db.ensureDeletionLogIndex();

      final rows = await db
          .customSelect(
            "SELECT deleted_at FROM deletion_log WHERE record_id = 'dup'",
          )
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.data['deleted_at'], 3000);
    },
  );

  test('sync_peer_cursors has applied_hlc_high column', () async {
    final db = DatabaseService.instance.database;
    final cols = await db
        .customSelect('PRAGMA table_info(sync_peer_cursors)')
        .get();
    expect(cols.map((r) => r.data['name']), contains('applied_hlc_high'));
  });

  test(
    'clearAcknowledgedDeletions honors hlc bound, floor, and null hlc',
    () async {
      final db = DatabaseService.instance.database;
      Future<void> seed(
        String id,
        int deletedAt,
        String? hlc,
      ) => db.customStatement(
        "INSERT INTO deletion_log (id, entity_type, record_id, deleted_at, hlc) "
        "VALUES ('$id', 'dives', '$id', $deletedAt, ${hlc == null ? 'NULL' : "'$hlc'"})",
      );
      await seed('acked-old', 100, '00000000000010:000000:x');
      await seed('unacked-old', 100, '00000000000050:000000:x');
      await seed('acked-young', 9000, '00000000000011:000000:x');
      await seed('no-hlc', 100, null);

      await SyncRepository().clearAcknowledgedDeletions(
        upToHlc: '00000000000020:000000:x',
        floorCutoffMillis: 5000,
      );

      final left = (await SyncRepository().getAllDeletions())
          .map((d) => d.recordId)
          .toSet();
      expect(left, {'unacked-old', 'acked-young', 'no-hlc'});
    },
  );

  test(
    'clearAcknowledgedDeletions with null upToHlc clears everything past the floor',
    () async {
      final repo = SyncRepository();
      await repo.logDeletion(
        entityType: 'dives',
        recordId: 'old',
        deletedAt: 100,
      );
      await repo.logDeletion(
        entityType: 'dives',
        recordId: 'new',
        deletedAt: 9000,
      );
      await repo.clearAcknowledgedDeletions(
        upToHlc: null,
        floorCutoffMillis: 5000,
      );
      final left = (await repo.getAllDeletions())
          .map((d) => d.recordId)
          .toSet();
      expect(left, {'new'});
    },
  );
}
