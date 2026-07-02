import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';
import 'package:submersion/features/dive_log/data/repositories/dive_repository_impl.dart';
import 'package:submersion/features/dive_log/data/services/dive_consolidation_service.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart'
    as domain;

import '../../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late DiveRepository diveRepo;
  late DiveConsolidationService service;

  setUp(() async {
    db = await setUpTestDatabase();
    await db.customStatement('PRAGMA foreign_keys = OFF');
    diveRepo = DiveRepository();
    service = DiveConsolidationService(diveRepo);
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  domain.DiveTank tank(
    String id, {
    required double o2,
    double he = 0,
    double? start,
    double? end,
    int order = 0,
  }) => domain.DiveTank(
    id: id,
    gasMix: domain.GasMix(o2: o2, he: he),
    startPressure: start,
    endPressure: end,
    order: order,
  );

  /// Seeds a dive via the repository (base row, tanks, profile) and, when
  /// [computerId] is given, stamps the raw `dives.computerId` FK column the
  /// same way a real download does (the domain Dive entity has no
  /// computerId field, so createDive can never set it -- see
  /// dive_repository_impl.dart:4481-4482).
  Future<void> seedDive(
    String id, {
    required DateTime entry,
    int runtimeMin = 30,
    double depth = 18,
    String? computerId,
    String? serial,
    List<domain.DiveTank> tanks = const [],
    List<domain.DiveProfilePoint>? profile,
  }) async {
    await diveRepo.createDive(
      domain.Dive(
        id: id,
        diverId: 'diver1',
        dateTime: entry,
        entryTime: entry,
        runtime: Duration(minutes: runtimeMin),
        maxDepth: depth,
        diveComputerSerial: serial,
        tanks: tanks,
        profile:
            profile ??
            [
              const domain.DiveProfilePoint(timestamp: 0, depth: 0),
              domain.DiveProfilePoint(
                timestamp: runtimeMin * 30,
                depth: depth,
                temperature: 22.5,
                tts: 5,
                cns: 10.0,
              ),
              domain.DiveProfilePoint(timestamp: runtimeMin * 60, depth: 0),
            ],
      ),
    );
    if (computerId != null) {
      await (db.update(db.dives)..where((t) => t.id.equals(id))).write(
        DivesCompanion(computerId: Value(computerId)),
      );
    }
  }

  Future<void> seedDataSource(
    String id, {
    required String diveId,
    String? computerId,
    bool isPrimary = true,
    Uint8List? rawData,
    Uint8List? rawFingerprint,
  }) async {
    await db
        .into(db.diveDataSources)
        .insert(
          DiveDataSourcesCompanion.insert(
            id: id,
            diveId: diveId,
            importedAt: DateTime.utc(2026, 7, 1),
            createdAt: DateTime.utc(2026, 7, 1),
          ).copyWith(
            isPrimary: Value(isPrimary),
            computerId: Value(computerId),
            rawData: Value(rawData),
            rawFingerprint: Value(rawFingerprint),
          ),
        );
  }

  Future<void> seedTankPressure(
    String id, {
    required String diveId,
    required String tankId,
    required int timestamp,
    required double pressure,
  }) async {
    await db
        .into(db.tankPressureProfiles)
        .insert(
          TankPressureProfilesCompanion.insert(
            id: id,
            diveId: diveId,
            tankId: tankId,
            timestamp: timestamp,
            pressure: pressure,
          ),
        );
  }

  Future<void> seedEvent(
    String id, {
    required String diveId,
    required int timestamp,
    String eventType = 'gaschange',
    String? tankId,
  }) async {
    await db
        .into(db.diveProfileEvents)
        .insert(
          DiveProfileEventsCompanion.insert(
            id: id,
            diveId: diveId,
            timestamp: timestamp,
            eventType: eventType,
            createdAt: 0,
          ).copyWith(tankId: Value(tankId)),
        );
  }

  Future<void> seedGasSwitch(
    String id, {
    required String diveId,
    required String tankId,
    required int timestamp,
  }) async {
    await db
        .into(db.gasSwitches)
        .insert(
          GasSwitchesCompanion.insert(
            id: id,
            diveId: diveId,
            timestamp: timestamp,
            tankId: tankId,
            createdAt: 0,
          ),
        );
  }

  Future<void> seedMedia(String id, {required String diveId}) async {
    await db
        .into(db.media)
        .insert(
          MediaCompanion.insert(
            id: id,
            filePath: '/photos/$id.jpg',
            createdAt: 0,
            updatedAt: 0,
          ).copyWith(diveId: Value(diveId)),
        );
  }

  /// Two overlapping dives (target 't', secondary 's', 60s apart) each with
  /// a computer, a data source, a profile carrying temp/tts/cns, two tanks
  /// (one dedupable pair: tank-t1 <-> tank-s1), tank pressures, two events,
  /// and (on the secondary only) one media row.
  Future<void> seedConsolidatableFixture() async {
    await seedDive(
      't',
      entry: DateTime.utc(2026, 7, 1, 9),
      computerId: 'comp-t',
      serial: 'SER-T',
      tanks: [
        tank('tank-t1', o2: 21, start: 200, end: 100, order: 0),
        tank('tank-t2', o2: 32, start: 200, end: 120, order: 1),
      ],
    );
    await seedDataSource('src-t', diveId: 't', computerId: 'comp-t');
    await seedTankPressure(
      'tp-t1',
      diveId: 't',
      tankId: 'tank-t1',
      timestamp: 60,
      pressure: 190,
    );
    await seedTankPressure(
      'tp-t2',
      diveId: 't',
      tankId: 'tank-t2',
      timestamp: 60,
      pressure: 190,
    );
    await seedEvent('event-t1', diveId: 't', timestamp: 30, tankId: 'tank-t1');
    await seedEvent('event-t2', diveId: 't', timestamp: 900, eventType: 'deco');

    await seedDive(
      's',
      entry: DateTime.utc(2026, 7, 1, 9, 1), // 60s after target
      computerId: 'comp-s',
      serial: 'SER-S',
      tanks: [
        // Dedupable: same gas, pressures within the 5 bar tolerance of
        // tank-t1.
        tank('tank-s1', o2: 21, start: 205, end: 105, order: 0),
        // Not dedupable: pure O2 deco bottle.
        tank('tank-s2', o2: 100, start: 200, end: 150, order: 1),
      ],
    );
    await seedDataSource('src-s', diveId: 's', computerId: 'comp-s');
    await seedTankPressure(
      'tp-s1',
      diveId: 's',
      tankId: 'tank-s1',
      timestamp: 60,
      pressure: 195,
    );
    await seedTankPressure(
      'tp-s2',
      diveId: 's',
      tankId: 'tank-s2',
      timestamp: 60,
      pressure: 195,
    );
    await seedEvent('event-s1', diveId: 's', timestamp: 30, tankId: 'tank-s1');
    await seedGasSwitch(
      'switch-s1',
      diveId: 's',
      tankId: 'tank-s1',
      timestamp: 30,
    );
    await seedEvent('event-s2', diveId: 's', timestamp: 900, eventType: 'deco');
    await seedMedia('media-s', diveId: 's');
  }

  group('apply', () {
    test(
      'scenario 1: re-parents everything and tombstones the secondary',
      () async {
        await seedConsolidatableFixture();

        final outcome = await service.apply(
          targetDiveId: 't',
          secondaryDiveIds: ['s'],
        );
        expect(outcome.targetDiveId, 't');

        // Target has both computers' profile rows.
        final profile =
            await (db.select(db.diveProfiles)
                  ..where((t) => t.diveId.equals('t'))
                  ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]))
                .get();
        expect(profile, hasLength(6)); // 3 target + 3 secondary

        // Secondary's profile timestamps shifted by +60 and carry the
        // secondary's computerId. (FK enforcement is off in this suite, so
        // the original orphaned secondary rows -- still diveId='s' -- also
        // linger in the table; filtering by diveId='t' above already
        // excludes them here.)
        final secondaryProfile = profile.where((p) => p.computerId == 'comp-s');
        expect(secondaryProfile.map((p) => p.timestamp).toSet(), {
          60,
          960,
          1860,
        });
        expect(
          secondaryProfile.every(
            (p) => p.computerId == 'comp-s' && !p.isPrimary,
          ),
          isTrue,
        );

        // Secondary's events shifted by +60 and carry the secondary's
        // computerId.
        final events = await (db.select(
          db.diveProfileEvents,
        )..where((t) => t.diveId.equals('t'))).get();
        // Re-parented events get fresh ids (the originals are left behind
        // under diveId='s' since FK enforcement is off in this suite), so
        // identify them by computerId attribution instead.
        final secondaryEvents = events.where((e) => e.computerId == 'comp-s');
        expect(secondaryEvents.map((e) => e.timestamp).toSet(), {90, 960});
        expect(secondaryEvents.every((e) => e.computerId == 'comp-s'), isTrue);

        // Secondary's tank pressures shifted by +60 and carry the
        // secondary's computerId.
        final pressures = await (db.select(
          db.tankPressureProfiles,
        )..where((t) => t.diveId.equals('t'))).get();
        final secondaryPressures = pressures.where(
          (p) => p.computerId == 'comp-s',
        );
        expect(secondaryPressures.map((p) => p.timestamp).toSet(), {120});
        expect(
          secondaryPressures.every((p) => p.computerId == 'comp-s'),
          isTrue,
        );

        // Secondary dive row gone, tombstoned.
        final remaining = await db.select(db.dives).get();
        expect(remaining.map((r) => r.id), ['t']);
        final tombstones = await (db.select(
          db.deletionLog,
        )..where((t) => t.entityType.equals('dives'))).get();
        expect(tombstones.map((t) => t.recordId).toSet(), {'s'});
      },
    );

    test(
      'scenario 2: dedups matching tanks, keeps non-matching with attribution',
      () async {
        await seedConsolidatableFixture();

        await service.apply(targetDiveId: 't', secondaryDiveIds: ['s']);

        final tanks =
            await (db.select(db.diveTanks)
                  ..where((t) => t.diveId.equals('t'))
                  ..orderBy([(t) => OrderingTerm.asc(t.tankOrder)]))
                .get();
        // tank-s1 deduped into tank-t1: no new row. tank-s2 kept, fresh id.
        expect(tanks, hasLength(3));
        expect(tanks.map((t) => t.id), contains('tank-t1'));
        expect(tanks.map((t) => t.id), contains('tank-t2'));
        expect(tanks.map((t) => t.id), isNot(contains('tank-s1')));

        final newTank = tanks.firstWhere(
          (t) => t.id != 'tank-t1' && t.id != 'tank-t2',
        );
        expect(newTank.computerId, 'comp-s');
        expect(newTank.tankOrder, 2); // continues after target's 0, 1.

        // The dedupable tank's pressure series lands on tank-t1's id with
        // the secondary's computerId.
        final tankT1Pressures = await (db.select(
          db.tankPressureProfiles,
        )..where((t) => t.tankId.equals('tank-t1'))).get();
        expect(tankT1Pressures, hasLength(2)); // original + folded-in
        final foldedIn = tankT1Pressures.firstWhere((p) => p.id != 'tp-t1');
        expect(foldedIn.computerId, 'comp-s');
        expect(foldedIn.timestamp, 120); // 60 + 60s offset

        // The non-dedupable tank's pressure series lands on the fresh id.
        final newTankPressures = await (db.select(
          db.tankPressureProfiles,
        )..where((t) => t.tankId.equals(newTank.id))).get();
        expect(newTankPressures, hasLength(1));
        expect(newTankPressures.single.computerId, 'comp-s');
      },
    );

    test('scenario 3: dive_data_sources ends with a primary row plus the '
        'secondary re-pointed, non-primary, raw bytes preserved', () async {
      await seedDive(
        't',
        entry: DateTime.utc(2026, 7, 1, 9),
        computerId: 'comp-t',
        serial: 'SER-T',
      );
      await seedDive(
        's',
        entry: DateTime.utc(2026, 7, 1, 9, 1),
        computerId: 'comp-s',
        serial: 'SER-S',
      );
      await seedDataSource('src-t', diveId: 't', computerId: 'comp-t');
      await seedDataSource(
        'src-s',
        diveId: 's',
        computerId: 'comp-s',
        rawData: Uint8List.fromList([1, 2, 3]),
        rawFingerprint: Uint8List.fromList([9, 9]),
      );

      await service.apply(targetDiveId: 't', secondaryDiveIds: ['s']);

      final sources = await (db.select(
        db.diveDataSources,
      )..where((t) => t.diveId.equals('t'))).get();
      expect(sources, hasLength(2));
      expect(sources.where((s) => s.isPrimary), hasLength(1));
      final repointed = sources.firstWhere((s) => !s.isPrimary);
      expect(repointed.computerId, 'comp-s');
      expect(repointed.rawData, [1, 2, 3]);
      expect(repointed.rawFingerprint, [9, 9]);
    });

    test('scenario 4: stamps pre-existing target children with the primary '
        "computer on first consolidation", () async {
      await seedDive(
        't',
        entry: DateTime.utc(2026, 7, 1, 9),
        computerId: 'comp-t',
        serial: 'SER-T',
        tanks: [tank('tank-t1', o2: 21)],
      );
      await seedDive(
        's',
        entry: DateTime.utc(2026, 7, 1, 9, 1),
        computerId: 'comp-s',
        serial: 'SER-S',
      );

      final before = await (db.select(
        db.diveTanks,
      )..where((t) => t.id.equals('tank-t1'))).getSingle();
      expect(before.computerId, isNull);

      await service.apply(targetDiveId: 't', secondaryDiveIds: ['s']);

      final targetRow = await (db.select(
        db.dives,
      )..where((t) => t.id.equals('t'))).getSingle();
      final after = await (db.select(
        db.diveTanks,
      )..where((t) => t.id.equals('tank-t1'))).getSingle();
      expect(after.computerId, targetRow.computerId);
      expect(after.computerId, 'comp-t');
    });

    test('scenario 5: events preserved with attribution; gas switches '
        'remapped to merged tank ids', () async {
      await seedConsolidatableFixture();

      await service.apply(targetDiveId: 't', secondaryDiveIds: ['s']);

      // event-s1 is re-parented under a fresh id (the original id's row
      // is left behind under diveId='s' since FK enforcement is off in
      // this suite), so locate it by its new diveId + shifted timestamp.
      final event =
          await (db.select(db.diveProfileEvents)
                ..where((t) => t.diveId.equals('t') & t.timestamp.equals(90)))
              .getSingle();
      // event-s1 originally referenced tank-s1, which deduped into
      // tank-t1.
      expect(event.tankId, isNot('tank-s1'));
      final tankT1 = await (db.select(
        db.diveTanks,
      )..where((t) => t.id.equals('tank-t1'))).getSingle();
      expect(event.tankId, tankT1.id);
      expect(event.computerId, 'comp-s');
      expect(event.diveId, 't');

      final gasSwitches = await (db.select(
        db.gasSwitches,
      )..where((t) => t.diveId.equals('t'))).get();
      expect(gasSwitches, hasLength(1));
      expect(gasSwitches.single.tankId, tankT1.id);
      expect(gasSwitches.single.timestamp, 90);
    });

    test('scenario 6: media re-pointed to the target', () async {
      await seedConsolidatableFixture();

      await service.apply(targetDiveId: 't', secondaryDiveIds: ['s']);

      final media = await (db.select(
        db.media,
      )..where((t) => t.id.equals('media-s'))).getSingle();
      expect(media.diveId, 't');
    });

    test(
      'scenario 7: rejects a same-computer selection; nothing written',
      () async {
        await seedDive(
          't2',
          entry: DateTime.utc(2026, 7, 1, 9),
          computerId: 'comp-x',
        );
        await seedDive(
          's2',
          entry: DateTime.utc(2026, 7, 1, 9),
          computerId: 'comp-x',
        );

        expect(
          () => service.apply(targetDiveId: 't2', secondaryDiveIds: ['s2']),
          throwsArgumentError,
        );

        final remaining = await db.select(db.dives).get();
        expect(remaining.map((r) => r.id).toSet(), {'t2', 's2'});
        expect(await db.select(db.deletionLog).get(), isEmpty);
      },
    );

    test(
      'scenario 9: a second consolidation unions sources without nesting',
      () async {
        await seedConsolidatableFixture();
        await seedDive(
          'u',
          entry: DateTime.utc(2026, 7, 1, 9, 5),
          computerId: 'comp-u',
          serial: 'SER-U',
        );
        await seedDataSource('src-u', diveId: 'u', computerId: 'comp-u');

        await service.apply(targetDiveId: 't', secondaryDiveIds: ['s']);
        await service.apply(targetDiveId: 't', secondaryDiveIds: ['u']);

        final sources = await (db.select(
          db.diveDataSources,
        )..where((t) => t.diveId.equals('t'))).get();
        expect(sources, hasLength(3));
        expect(sources.where((s) => s.isPrimary), hasLength(1));
        expect(sources.map((s) => s.computerId).toSet(), {
          'comp-t',
          'comp-s',
          'comp-u',
        });
      },
    );
  });

  group('undo', () {
    test(
      'scenario 8: restores both dives byte-for-byte, works with FK ON',
      () async {
        await db.customStatement('PRAGMA foreign_keys = ON');

        await db
            .into(db.divers)
            .insert(
              const DiversCompanion(
                id: Value('diver1'),
                name: Value('diver1'),
                createdAt: Value(0),
                updatedAt: Value(0),
              ),
            );
        for (final computerId in ['comp-t', 'comp-s']) {
          await db
              .into(db.diveComputers)
              .insert(
                DiveComputersCompanion.insert(
                  id: computerId,
                  name: computerId,
                  createdAt: 0,
                  updatedAt: 0,
                ),
              );
        }

        await seedConsolidatableFixture();

        final beforeDives = await (db.select(
          db.dives,
        )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

        final outcome = await service.apply(
          targetDiveId: 't',
          secondaryDiveIds: ['s'],
        );
        await service.undo(outcome.snapshot);

        final afterDives = await (db.select(
          db.dives,
        )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
        expect(afterDives.map((r) => r.id), ['s', 't']);
        for (var i = 0; i < beforeDives.length; i++) {
          expect(
            afterDives[i].copyWith(updatedAt: 0, hlc: const Value(null)),
            beforeDives[i].copyWith(updatedAt: 0, hlc: const Value(null)),
          );
        }

        // Children restored with original ids.
        final tanks = await db.select(db.diveTanks).get();
        expect(tanks.map((t) => t.id).toSet(), {
          'tank-t1',
          'tank-t2',
          'tank-s1',
          'tank-s2',
        });
        final events = await db.select(db.diveProfileEvents).get();
        expect(events.map((e) => e.id).toSet(), {
          'event-t1',
          'event-t2',
          'event-s1',
          'event-s2',
        });
        final switches = await db.select(db.gasSwitches).get();
        expect(switches.map((s) => s.id).toSet(), {'switch-s1'});
        final sources = await db.select(db.diveDataSources).get();
        expect(sources.every((s) => s.isPrimary), isTrue);

        // Media pointer restored to the secondary.
        final media = await (db.select(
          db.media,
        )..where((t) => t.id.equals('media-s'))).getSingle();
        expect(media.diveId, 's');

        // Target dive was modified, not created: undo must not tombstone
        // it -- only the secondary's original tombstone (from apply) plus
        // undo's own bookkeeping should reference 's', never 't'.
        final targetTombstones = await (db.select(
          db.deletionLog,
        )..where((t) => t.recordId.equals('t'))).get();
        expect(targetTombstones, isEmpty);
      },
    );
  });
}
