import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:submersion/core/database/database.dart';
import 'package:submersion/features/safety/data/repositories/incident_repository.dart';
import 'package:submersion/features/safety/domain/entities/incident.dart';

import '../../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late IncidentRepository repo;
  final when = DateTime.utc(2026, 7, 15, 10);

  setUp(() async {
    db = await setUpTestDatabase();
    repo = IncidentRepository();
  });

  tearDown(() => tearDownTestDatabase());

  Future<void> insertDive(String id) async {
    final now = when.millisecondsSinceEpoch;
    await db
        .into(db.dives)
        .insert(
          DivesCompanion(
            id: Value(id),
            diveDateTime: Value(now),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  test('create, read, update, delete round-trip with tombstone', () async {
    final created = await repo.createIncident(
      occurredAt: when,
      category: IncidentCategory.gasSupply,
      severity: IncidentSeverity.moderate,
      narrative: 'Free-flow at 18 m; switched to buddy octo and ascended.',
      lessonsLearned: 'Service the regulator before cold-water trips.',
    );

    final listed = await repo.getIncidents();
    expect(listed, hasLength(1));
    expect(listed.single.category, IncidentCategory.gasSupply);

    await repo.updateIncident(
      created.copyWith(severity: IncidentSeverity.serious),
    );
    expect(
      (await repo.getIncidentById(created.id))!.severity,
      IncidentSeverity.serious,
    );

    await repo.deleteIncident(created.id);
    expect(await repo.getIncidents(), isEmpty);
    final tombstones = await db.select(db.deletionLog).get();
    expect(tombstones.map((t) => t.entityType), contains('incidents'));
  });

  test('dive link survives dive deletion (severed, not cascaded)', () async {
    await insertDive('dive-1');
    final incident = await repo.createIncident(
      occurredAt: when,
      category: IncidentCategory.buoyancy,
      severity: IncidentSeverity.minor,
      narrative: 'Runaway ascent from 5 m caught by buddy.',
      diveId: 'dive-1',
    );
    expect(await repo.getIncidentsForDive('dive-1'), hasLength(1));

    await (db.delete(db.dives)..where((t) => t.id.equals('dive-1'))).go();

    final survived = await repo.getIncidentById(incident.id);
    expect(survived, isNotNull);
    expect(survived!.diveId, isNull);
  });
}
