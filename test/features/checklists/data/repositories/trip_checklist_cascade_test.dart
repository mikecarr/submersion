import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/services/database_service.dart';
import 'package:submersion/features/checklists/data/repositories/trip_checklist_repository.dart';
import 'package:submersion/features/checklists/domain/entities/trip_checklist_item.dart';
import 'package:submersion/features/trips/data/repositories/trip_repository.dart';
import 'package:submersion/features/trips/domain/entities/trip.dart';

import '../../../../helpers/test_database.dart';

void main() {
  setUp(() async {
    await setUpTestDatabase();
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  test(
    'deleting a trip deletes its checklist items and tombstones them',
    () async {
      final tripRepository = TripRepository();
      final checklistRepository = TripChecklistRepository();

      final trip = await tripRepository.createTrip(
        Trip(
          id: '',
          name: 'Cascade',
          startDate: DateTime(2026, 9, 10),
          endDate: DateTime(2026, 9, 17),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      final item = await checklistRepository.createItem(
        TripChecklistItem(
          id: '',
          tripId: trip.id,
          title: 'Pack fins',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      await tripRepository.deleteTrip(trip.id);

      // Items gone (FK would also have blocked the trip delete otherwise).
      expect(await checklistRepository.getByTripId(trip.id), isEmpty);

      // Tombstone written for the checklist item.
      final db = DatabaseService.instance.database;
      final tombstones = await db
          .customSelect(
            "SELECT record_id FROM deletion_log WHERE entity_type = 'tripChecklistItems'",
          )
          .get();
      expect(
        tombstones.map((r) => r.read<String>('record_id')),
        contains(item.id),
      );
    },
  );
}
