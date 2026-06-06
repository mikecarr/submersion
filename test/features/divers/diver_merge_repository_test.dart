import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';
import 'package:submersion/core/services/database_service.dart';
import 'package:submersion/features/divers/data/repositories/diver_merge_repository.dart';
import 'package:submersion/features/divers/domain/entities/diver.dart'
    as domain;

import '../../helpers/test_database.dart';

domain.Diver makeDiver(
  String id,
  String name, {
  bool isDefault = false,
  int createdAt = 0,
}) {
  return domain.Diver(
    id: id,
    name: name,
    isDefault: isDefault,
    createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
  );
}

/// Exhaustive, schema-driven coverage for diver merge.
///
/// Rather than hand-seed 16 hand-written Companion rows (brittle against schema
/// changes), this test discovers every table that has a `diver_id` column via
/// SQLite's catalog, seeds one minimal row per table pointing at the duplicate,
/// runs the merge, then sweeps every such table asserting no row still points
/// at the deleted duplicate. Any future table that gains a diver_id is covered
/// automatically.
void main() {
  late AppDatabase db;
  late DiverMergeRepository repo;

  const keeper = 'diver-keeper';
  const dup = 'diver-dup';

  setUp(() async {
    db = await setUpTestDatabase();
    repo = DiverMergeRepository();

    for (final id in [keeper, dup]) {
      await db
          .into(db.divers)
          .insert(
            DiversCompanion.insert(
              id: id,
              name: 'Alex Diver',
              createdAt: 1000,
              updatedAt: 1000,
            ),
          );
    }
  });

  tearDown(() {
    DatabaseService.instance.resetForTesting();
  });

  /// All user tables (excluding the divers table itself) that have a
  /// `diver_id` column, discovered from the live schema.
  Future<List<String>> tablesWithDiverId() async {
    final rows = await db
        .customSelect(
          "SELECT m.name AS tbl FROM sqlite_master m "
          "JOIN pragma_table_info(m.name) p "
          "WHERE m.type = 'table' AND p.name = 'diver_id' "
          "AND m.name != 'divers'",
        )
        .get();
    return rows.map((r) => r.read<String>('tbl')).toList();
  }

  Future<int> countByDiver(String table, String diverId) async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM "$table" WHERE diver_id = ?',
          variables: [Variable.withString(diverId)],
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// Column names for [table] that are NOT NULL and have no default, so a
  /// minimal INSERT can satisfy them.
  Future<List<({String name, String type})>> requiredColumns(
    String table,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT * FROM pragma_table_info(?)',
          variables: [Variable.withString(table)],
        )
        .get();
    return rows
        .where(
          (r) =>
              (r.data['notnull'] as int? ?? 0) == 1 &&
              r.data['dflt_value'] == null,
        )
        .map(
          (r) => (
            name: r.data['name'] as String,
            type: (r.data['type'] as String?) ?? '',
          ),
        )
        .toList();
  }

  /// Insert one minimal row into [table] with diver_id = [diverId], filling
  /// every required column with a type-appropriate placeholder.
  Future<void> seedRow(String table, String diverId, String pk) async {
    final cols = await requiredColumns(table);
    final names = <String>[];
    final placeholders = <String>[];
    final vars = <Variable>[];
    for (final col in cols) {
      names.add('"${col.name}"');
      placeholders.add('?');
      if (col.name == 'diver_id') {
        vars.add(Variable.withString(diverId));
      } else if (col.name == 'id') {
        vars.add(Variable.withString(pk));
      } else {
        final t = col.type.toUpperCase();
        if (t.contains('INT')) {
          vars.add(Variable.withInt(0));
        } else if (t.contains('REAL') ||
            t.contains('FLOA') ||
            t.contains('DOUB')) {
          vars.add(Variable.withReal(0));
        } else if (t.contains('BLOB')) {
          vars.add(Variable.withBlob(Uint8List(0)));
        } else {
          vars.add(Variable.withString('x'));
        }
      }
    }
    // Ensure diver_id present even if it was nullable (not in requiredColumns).
    if (!names.contains('"diver_id"')) {
      names.add('"diver_id"');
      placeholders.add('?');
      vars.add(Variable.withString(diverId));
    }
    // Ensure a primary key id present even if nullable.
    if (!names.contains('"id"')) {
      names.add('"id"');
      placeholders.add('?');
      vars.add(Variable.withString(pk));
    }
    await db.customStatement(
      'INSERT INTO "$table" (${names.join(",")}) '
      'VALUES (${placeholders.join(",")})',
      vars.map((v) => v.value).toList(),
    );
  }

  test('every diver_id table is repointed or cleared; none reference the '
      'duplicate after merge', () async {
    final tables = await tablesWithDiverId();
    expect(tables, isNotEmpty, reason: 'sanity: schema has diver_id tables');

    // Seed one duplicate-owned row per table.
    var i = 0;
    for (final table in tables) {
      await seedRow(table, dup, 'row-$i');
      i++;
      expect(
        await countByDiver(table, dup),
        1,
        reason: 'precondition: $table seeded with a duplicate-owned row',
      );
    }

    await repo.mergeDivers(keeperId: keeper, duplicateId: dup);

    for (final table in tables) {
      expect(
        await countByDiver(table, dup),
        0,
        reason: '$table still references the deleted duplicate after merge',
      );
    }
  });

  test('the duplicate diver row is deleted and the keeper remains', () async {
    await repo.mergeDivers(keeperId: keeper, duplicateId: dup);
    final ids = (await db.select(db.divers).get()).map((d) => d.id).toSet();
    expect(ids, contains(keeper));
    expect(ids, isNot(contains(dup)));
  });

  test('additive data is preserved on the keeper, not lost', () async {
    // A dive owned by the duplicate must survive, now owned by the keeper.
    await db
        .into(db.dives)
        .insert(
          DivesCompanion.insert(
            id: 'dive-keepme',
            diveDateTime: 2000,
            diverId: const Value(dup),
            createdAt: 2000,
            updatedAt: 2000,
          ),
        );

    await repo.mergeDivers(keeperId: keeper, duplicateId: dup);

    expect(await countByDiver('dives', keeper), 1);
    final dive = await (db.select(
      db.dives,
    )..where((t) => t.id.equals('dive-keepme'))).getSingleOrNull();
    expect(
      dive,
      isNotNull,
      reason: 'the dive must not be deleted by the merge',
    );
    expect(dive!.diverId, keeper);
  });

  test(
    'the duplicate deletion is logged so it propagates to other devices',
    () async {
      await repo.mergeDivers(keeperId: keeper, duplicateId: dup);
      final logged = await db
          .customSelect(
            "SELECT COUNT(*) AS c FROM deletion_log "
            "WHERE entity_type = 'divers' AND record_id = ?",
            variables: [Variable.withString(dup)],
          )
          .getSingle();
      expect(logged.read<int>('c'), 1);
    },
  );

  group('findDuplicateGroups', () {
    test('groups divers with the same normalized name', () {
      final groups = DiverMergeRepository.findDuplicateGroups([
        makeDiver('a', 'Alex Diver', createdAt: 100),
        makeDiver('b', ' alex diver ', createdAt: 200),
        makeDiver('c', 'Someone Else', createdAt: 300),
      ]);
      expect(groups, hasLength(1));
      expect(groups.first.duplicates, hasLength(1));
      expect(
        {groups.first.keeper.id, groups.first.duplicates.first.id},
        {'a', 'b'},
      );
    });

    test('prefers the default diver as keeper', () {
      final groups = DiverMergeRepository.findDuplicateGroups([
        makeDiver('old', 'Alex', createdAt: 100),
        makeDiver('default', 'Alex', isDefault: true, createdAt: 500),
      ]);
      expect(groups.first.keeper.id, 'default');
      expect(groups.first.duplicates.single.id, 'old');
    });

    test('falls back to the oldest diver when none is default', () {
      final groups = DiverMergeRepository.findDuplicateGroups([
        makeDiver('newer', 'Alex', createdAt: 500),
        makeDiver('older', 'Alex', createdAt: 100),
      ]);
      expect(groups.first.keeper.id, 'older');
    });

    test('returns no groups when all names are distinct', () {
      final groups = DiverMergeRepository.findDuplicateGroups([
        makeDiver('a', 'Alex', createdAt: 100),
        makeDiver('b', 'Blair', createdAt: 200),
      ]);
      expect(groups, isEmpty);
    });
  });
}
