import 'package:flutter_test/flutter_test.dart';

import 'package:submersion/core/database/database.dart';
import 'package:submersion/features/safety/data/repositories/emergency_chamber_repository.dart';

import '../../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late EmergencyChamberRepository repo;

  setUp(() async {
    db = await setUpTestDatabase();
    repo = EmergencyChamberRepository();
  });

  tearDown(() => tearDownTestDatabase());

  test('create, list, delete round-trip with tombstone', () async {
    final created = await repo.createChamber(
      name: 'Local Chamber',
      country: 'US',
      phone: '+1-555-0100',
      city: 'Testville',
    );
    expect(created.isBuiltIn, isFalse);

    final chambers = await repo.getUserChambers();
    expect(chambers, hasLength(1));
    expect(chambers.single.name, 'Local Chamber');

    await repo.deleteChamber(created.id);
    expect(await repo.getUserChambers(), isEmpty);

    final tombstones = await db.select(db.deletionLog).get();
    expect(tombstones.map((t) => t.entityType), contains('emergencyChambers'));
  });
}
