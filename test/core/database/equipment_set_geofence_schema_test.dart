import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  test('equipment_sets.is_default defaults to false', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db
        .into(db.equipmentSets)
        .insert(
          EquipmentSetsCompanion.insert(
            id: 's1',
            name: 'Cold Water',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final row = await (db.select(
      db.equipmentSets,
    )..where((t) => t.id.equals('s1'))).getSingle();
    expect(row.isDefault, isFalse);
  });

  test(
    'equipment_set_geofences round-trips and cascades on set delete',
    () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db
          .into(db.equipmentSets)
          .insert(
            EquipmentSetsCompanion.insert(
              id: 's1',
              name: 'Cold Water',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.equipmentSetGeofences)
          .insert(
            EquipmentSetGeofencesCompanion.insert(
              id: 'g1',
              setId: 's1',
              latitude: 36.62,
              longitude: -121.9,
              radiusMeters: 24000,
              createdAt: now,
              updatedAt: now,
            ),
          );

      final geofences = await db.select(db.equipmentSetGeofences).get();
      expect(geofences, hasLength(1));
      expect(geofences.first.setId, 's1');

      await (db.delete(db.equipmentSets)..where((t) => t.id.equals('s1'))).go();
      final afterDelete = await db.select(db.equipmentSetGeofences).get();
      expect(
        afterDelete,
        isEmpty,
        reason: 'geofences cascade-delete with the set',
      );
    },
  );

  test('v112 (equipment sets/geofences) stays on the migration ladder', () {
    // Superseded-tripwire convention: this was the exact-latest tripwire when
    // v112 was newest. This branch adds v119 (equipment.lift_capacity_kg), so
    // the exact assertion is relaxed to greaterThanOrEqualTo -- the newest
    // migration's own test now holds the exact-latest tripwire.
    expect(AppDatabase.currentSchemaVersion, greaterThanOrEqualTo(112));
    expect(AppDatabase.migrationVersions, contains(112));
  });
}
