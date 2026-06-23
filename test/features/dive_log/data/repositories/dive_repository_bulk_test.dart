import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';
import 'package:submersion/features/dive_log/data/repositories/dive_repository_impl.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart'
    as domain;

import '../../../../helpers/test_database.dart';

void main() {
  late DiveRepository repository;
  late AppDatabase db;

  setUp(() async {
    db = await setUpTestDatabase();
    repository = DiveRepository();
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  Future<void> seed(String id, {String notes = ''}) => repository.createDive(
    domain.Dive(id: id, dateTime: DateTime(2026, 1, 1), notes: notes),
  );

  group('bulkUpdateFields', () {
    test(
      'writes only the given columns, bumps updatedAt, skips other dives',
      () async {
        await seed('d1', notes: 'keep');
        await seed('d2', notes: 'keep2');
        await seed('d3', notes: 'untouched');

        await repository.bulkUpdateFields([
          'd1',
          'd2',
        ], const DivesCompanion(rating: Value(5), waterType: Value('salt')));

        final r1 = await (db.select(
          db.dives,
        )..where((t) => t.id.equals('d1'))).getSingle();
        final r3 = await (db.select(
          db.dives,
        )..where((t) => t.id.equals('d3'))).getSingle();
        expect(r1.rating, 5);
        expect(r1.waterType, 'salt');
        expect(r1.notes, 'keep'); // untouched column preserved
        expect(r3.rating, isNull); // dive outside the id list untouched
        expect(r3.waterType, isNull);
      },
    );

    test('is a no-op for an empty id list', () async {
      await repository.bulkUpdateFields(
        const [],
        const DivesCompanion(rating: Value(3)),
      );
    });
  });

  group('bulkAppendNotes', () {
    test('appends to existing notes and to empty notes', () async {
      await seed('a', notes: 'Cozumel');
      await seed('b', notes: '');

      await repository.bulkAppendNotes(['a', 'b'], '\nGreat viz');

      final ra = await (db.select(
        db.dives,
      )..where((t) => t.id.equals('a'))).getSingle();
      final rb = await (db.select(
        db.dives,
      )..where((t) => t.id.equals('b'))).getSingle();
      expect(ra.notes, 'Cozumel\nGreat viz');
      expect(rb.notes, '\nGreat viz');
    });
  });

  group('bulkReplaceTags', () {
    setUp(() async {
      await db.customStatement('PRAGMA foreign_keys = OFF'); // test-only isolation
    });

    test('replaces existing tag membership with the given set', () async {
      await seed('d1');
      await repository.bulkAddTags(['d1'], ['old-tag']);

      await repository.bulkReplaceTags(['d1'], ['t1', 't2']);

      final rows = await (db.select(
        db.diveTags,
      )..where((t) => t.diveId.equals('d1'))).get();
      expect(rows.map((r) => r.tagId).toSet(), {'t1', 't2'});
    });
  });

  group('bulk equipment', () {
    setUp(() async {
      await db.customStatement('PRAGMA foreign_keys = OFF');
    });

    test('add then remove adjusts membership; replace overwrites', () async {
      await seed('d1');
      await repository.bulkAddEquipment(['d1'], ['e1', 'e2']);
      var rows = await (db.select(
        db.diveEquipment,
      )..where((t) => t.diveId.equals('d1'))).get();
      expect(rows.map((r) => r.equipmentId).toSet(), {'e1', 'e2'});

      await repository.bulkRemoveEquipment(['d1'], ['e1']);
      rows = await (db.select(
        db.diveEquipment,
      )..where((t) => t.diveId.equals('d1'))).get();
      expect(rows.map((r) => r.equipmentId).toSet(), {'e2'});

      await repository.bulkReplaceEquipment(['d1'], ['e9']);
      rows = await (db.select(
        db.diveEquipment,
      )..where((t) => t.diveId.equals('d1'))).get();
      expect(rows.map((r) => r.equipmentId).toSet(), {'e9'});
    });
  });
}
