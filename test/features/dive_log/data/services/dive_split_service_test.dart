import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';
import 'package:submersion/features/dive_log/data/repositories/dive_repository_impl.dart';
import 'package:submersion/features/dive_log/data/services/dive_consolidation_service.dart';
import 'package:submersion/features/dive_log/data/services/dive_split_service.dart';

import '../../../../helpers/test_database.dart';

void main() {
  late DiveRepository repository;
  late DiveSplitService service;
  late AppDatabase db;

  final baseTime = DateTime.utc(2026, 5, 7, 14, 6).millisecondsSinceEpoch;

  Future<void> insertComputer(String id, String name) async {
    await db
        .into(db.diveComputers)
        .insert(
          DiveComputersCompanion(
            id: Value(id),
            name: Value(name),
            createdAt: Value(baseTime),
            updatedAt: Value(baseTime),
          ),
        );
  }

  Future<void> insertDive(String id, {String? computerId}) async {
    await db
        .into(db.dives)
        .insert(
          DivesCompanion(
            id: Value(id),
            diveDateTime: Value(baseTime),
            computerId: Value(computerId),
            entryTime: Value(baseTime),
            exitTime: Value(baseTime + 56 * 60 * 1000),
            maxDepth: const Value(21.7),
            createdAt: Value(baseTime),
            updatedAt: Value(baseTime),
          ),
        );
  }

  Future<void> insertSource(
    String id,
    String diveId,
    String? computerId, {
    required bool isPrimary,
    double? maxDepth,
    DateTime? createdAt,
  }) async {
    await db
        .into(db.diveDataSources)
        .insert(
          DiveDataSourcesCompanion(
            id: Value(id),
            diveId: Value(diveId),
            computerId: Value(computerId),
            isPrimary: Value(isPrimary),
            maxDepth: Value(maxDepth),
            importedAt: Value(createdAt ?? DateTime.utc(2026, 1, 1)),
            createdAt: Value(createdAt ?? DateTime.utc(2026, 1, 1)),
          ),
        );
  }

  var rowCounter = 0;
  Future<String> insertProfileRow(
    String diveId,
    String? computerId, {
    required bool isPrimary,
    int timestamp = 0,
    double depth = 10.0,
  }) async {
    final id = 'prof-${rowCounter++}';
    await db
        .into(db.diveProfiles)
        .insert(
          DiveProfilesCompanion(
            id: Value(id),
            diveId: Value(diveId),
            computerId: Value(computerId),
            isPrimary: Value(isPrimary),
            timestamp: Value(timestamp),
            depth: Value(depth),
          ),
        );
    return id;
  }

  Future<String> insertTank(String diveId, String? computerId) async {
    final id = 'tank-${rowCounter++}';
    await db
        .into(db.diveTanks)
        .insert(
          DiveTanksCompanion(
            id: Value(id),
            diveId: Value(diveId),
            computerId: Value(computerId),
            tankOrder: const Value(0),
          ),
        );
    return id;
  }

  Future<String> insertTankPressure(
    String diveId,
    String tankId,
    String? computerId,
  ) async {
    final id = 'tp-${rowCounter++}';
    await db
        .into(db.tankPressureProfiles)
        .insert(
          TankPressureProfilesCompanion(
            id: Value(id),
            diveId: Value(diveId),
            tankId: Value(tankId),
            computerId: Value(computerId),
            timestamp: const Value(0),
            pressure: const Value(200.0),
          ),
        );
    return id;
  }

  Future<String> insertEvent(String diveId, String? computerId) async {
    final id = 'ev-${rowCounter++}';
    await db
        .into(db.diveProfileEvents)
        .insert(
          DiveProfileEventsCompanion(
            id: Value(id),
            diveId: Value(diveId),
            computerId: Value(computerId),
            timestamp: const Value(30),
            eventType: const Value('bookmark'),
            createdAt: Value(baseTime),
          ),
        );
    return id;
  }

  setUp(() async {
    db = await setUpTestDatabase();
    repository = DiveRepository();
    service = DiveSplitService(repository);
    rowCounter = 0;

    // Foreign keys must be enforced for these tests to be meaningful.
    final fk = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(fk.data.values.first, 1);

    await insertComputer('dc-a', 'Kiyans Teric');
    await insertComputer('dc-b', 'Erics Teric');
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  Future<List<String>> fkViolations() async {
    final rows = await db.customSelect('PRAGMA foreign_key_check').get();
    return rows.map((r) => r.data.toString()).toList();
  }

  test('splitting a secondary source moves its rows to a new dive', () async {
    await insertDive('dive-1', computerId: 'dc-a');
    await insertSource('src-a', 'dive-1', 'dc-a', isPrimary: true);
    await insertSource(
      'src-b',
      'dive-1',
      'dc-b',
      isPrimary: false,
      maxDepth: 18.3,
    );
    await insertProfileRow('dive-1', 'dc-a', isPrimary: true, depth: 21.7);
    await insertProfileRow(
      'dive-1',
      'dc-a',
      isPrimary: true,
      timestamp: 10,
      depth: 20.0,
    );
    await insertProfileRow('dive-1', 'dc-b', isPrimary: false, depth: 18.3);
    final tankB = await insertTank('dive-1', 'dc-b');
    await insertTankPressure('dive-1', tankB, 'dc-b');
    await insertEvent('dive-1', 'dc-b');

    final newDiveId = await service.split(diveId: 'dive-1', sourceId: 'src-b');

    // New dive carries the secondary's data, marked primary there.
    final newProfiles = await (db.select(
      db.diveProfiles,
    )..where((t) => t.diveId.equals(newDiveId))).get();
    expect(newProfiles.length, 1);
    expect(newProfiles.single.depth, 18.3);
    expect(newProfiles.single.isPrimary, isTrue);
    final newDive = await (db.select(
      db.dives,
    )..where((t) => t.id.equals(newDiveId))).getSingle();
    expect(newDive.computerId, 'dc-b');
    expect(newDive.maxDepth, 18.3);

    final newSources = await (db.select(
      db.diveDataSources,
    )..where((t) => t.diveId.equals(newDiveId))).get();
    expect(newSources.length, 1);
    expect(newSources.single.isPrimary, isTrue);

    // Original dive keeps only its own data.
    final oldProfiles = await (db.select(
      db.diveProfiles,
    )..where((t) => t.diveId.equals('dive-1'))).get();
    expect(oldProfiles.length, 2);
    expect(oldProfiles.every((r) => r.computerId == 'dc-a'), isTrue);
    final oldTanks = await (db.select(
      db.diveTanks,
    )..where((t) => t.diveId.equals('dive-1'))).get();
    expect(oldTanks, isEmpty);
    final oldSources = await (db.select(
      db.diveDataSources,
    )..where((t) => t.diveId.equals('dive-1'))).get();
    expect(oldSources.length, 1);
    expect(oldSources.single.id, 'src-a');

    expect(await fkViolations(), isEmpty);
  });

  test('splitting the primary promotes the remaining source', () async {
    await insertDive('dive-1', computerId: 'dc-a');
    await insertSource(
      'src-a',
      'dive-1',
      'dc-a',
      isPrimary: true,
      maxDepth: 21.7,
      createdAt: DateTime.utc(2026, 1, 1),
    );
    await insertSource(
      'src-b',
      'dive-1',
      'dc-b',
      isPrimary: false,
      maxDepth: 18.3,
      createdAt: DateTime.utc(2026, 1, 2),
    );
    await insertProfileRow('dive-1', 'dc-a', isPrimary: true, depth: 21.7);
    await insertProfileRow('dive-1', 'dc-b', isPrimary: false, depth: 18.3);

    final newDiveId = await service.split(diveId: 'dive-1', sourceId: 'src-a');

    final remaining = await (db.select(
      db.diveDataSources,
    )..where((t) => t.diveId.equals('dive-1'))).get();
    expect(remaining.length, 1);
    expect(remaining.single.id, 'src-b');
    expect(remaining.single.isPrimary, isTrue);

    final oldDive = await (db.select(
      db.dives,
    )..where((t) => t.id.equals('dive-1'))).getSingle();
    expect(oldDive.computerId, 'dc-b');
    expect(oldDive.maxDepth, 18.3);

    // Promoted source's profile rows become primary so getDiveProfile
    // (isPrimary filter) still returns a profile.
    final oldProfiles = await (db.select(
      db.diveProfiles,
    )..where((t) => t.diveId.equals('dive-1'))).get();
    expect(oldProfiles.single.computerId, 'dc-b');
    expect(oldProfiles.single.isPrimary, isTrue);

    final newProfiles = await (db.select(
      db.diveProfiles,
    )..where((t) => t.diveId.equals(newDiveId))).get();
    expect(newProfiles.single.depth, 21.7);

    expect(await fkViolations(), isEmpty);
  });

  test('splitting the only source throws and writes nothing', () async {
    await insertDive('dive-1', computerId: 'dc-a');
    await insertSource('src-a', 'dive-1', 'dc-a', isPrimary: true);
    await insertProfileRow('dive-1', 'dc-a', isPrimary: true);

    expect(
      () => service.split(diveId: 'dive-1', sourceId: 'src-a'),
      throwsArgumentError,
    );

    final dives = await db.select(db.dives).get();
    expect(dives.length, 1);
    final profiles = await db.select(db.diveProfiles).get();
    expect(profiles.length, 1);
  });

  test('split tombstones every moved row', () async {
    await insertDive('dive-1', computerId: 'dc-a');
    await insertSource('src-a', 'dive-1', 'dc-a', isPrimary: true);
    await insertSource('src-b', 'dive-1', 'dc-b', isPrimary: false);
    await insertProfileRow('dive-1', 'dc-a', isPrimary: true);
    final movedProfile = await insertProfileRow(
      'dive-1',
      'dc-b',
      isPrimary: false,
    );
    final movedTank = await insertTank('dive-1', 'dc-b');
    final movedPressure = await insertTankPressure('dive-1', movedTank, 'dc-b');
    final movedEvent = await insertEvent('dive-1', 'dc-b');

    await service.split(diveId: 'dive-1', sourceId: 'src-b');

    final tombstones = await db.select(db.deletionLog).get();
    final byRecord = {for (final t in tombstones) t.recordId: t.entityType};
    expect(byRecord[movedProfile], 'diveProfiles');
    expect(byRecord[movedTank], 'diveTanks');
    expect(byRecord[movedPressure], 'tankPressureProfiles');
    expect(byRecord[movedEvent], 'diveProfileEvents');
    expect(byRecord['src-b'], 'diveDataSources');
  });

  test(
    'consolidate then split restores an equivalent secondary dive',
    () async {
      await insertDive('dive-1', computerId: 'dc-a');
      await insertDive('dive-2', computerId: 'dc-b');
      await insertProfileRow('dive-1', null, isPrimary: true, depth: 21.7);
      await insertProfileRow('dive-2', null, isPrimary: true, depth: 18.3);
      await insertProfileRow(
        'dive-2',
        null,
        isPrimary: true,
        timestamp: 10,
        depth: 17.0,
      );

      final consolidation = DiveConsolidationService(repository);
      await consolidation.apply(
        targetDiveId: 'dive-1',
        secondaryDiveIds: ['dive-2'],
      );

      final sources = await (db.select(
        db.diveDataSources,
      )..where((t) => t.diveId.equals('dive-1'))).get();
      final secondarySource = sources.firstWhere((s) => s.computerId == 'dc-b');

      final newDiveId = await service.split(
        diveId: 'dive-1',
        sourceId: secondarySource.id,
      );

      final newProfiles = await (db.select(
        db.diveProfiles,
      )..where((t) => t.diveId.equals(newDiveId))).get();
      expect(newProfiles.length, 2);
      expect(
        newProfiles.map((p) => p.depth).reduce((a, b) => a > b ? a : b),
        18.3,
      );
      final newDive = await (db.select(
        db.dives,
      )..where((t) => t.id.equals(newDiveId))).getSingle();
      expect(newDive.computerId, 'dc-b');

      expect(await fkViolations(), isEmpty);
    },
  );
}
