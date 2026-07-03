import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/checklists/data/repositories/checklist_template_repository.dart';
import 'package:submersion/features/checklists/data/repositories/trip_checklist_repository.dart';
import 'package:submersion/features/checklists/domain/entities/checklist_template.dart';
import 'package:submersion/features/checklists/domain/entities/trip_checklist_item.dart';
import 'package:submersion/features/trips/data/repositories/trip_repository.dart';
import 'package:submersion/features/trips/domain/entities/trip.dart';

import '../../../../helpers/test_database.dart';

void main() {
  late TripChecklistRepository repository;
  late ChecklistTemplateRepository templateRepository;
  late TripRepository tripRepository;
  late Trip testTrip;

  final tripStart = DateTime(2026, 9, 10);

  TripChecklistItem item({
    String title = 'Service regulator',
    String? category,
    DateTime? dueDate,
  }) => TripChecklistItem(
    id: '',
    tripId: testTrip.id,
    title: title,
    category: category,
    dueDate: dueDate,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  setUp(() async {
    await setUpTestDatabase();
    repository = TripChecklistRepository();
    templateRepository = ChecklistTemplateRepository();
    tripRepository = TripRepository();
    // Parent trip satisfies the FK constraint (foreign_keys = ON in tests).
    testTrip = await tripRepository.createTrip(
      Trip(
        id: '',
        name: 'Red Sea',
        startDate: tripStart,
        endDate: tripStart.add(const Duration(days: 7)),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  group('CRUD', () {
    test('create, read ordered, update, toggle, delete', () async {
      final a = await repository.createItem(item(title: 'A'));
      await repository.createItem(item(title: 'B', category: 'Gear'));
      var items = await repository.getByTripId(testTrip.id);
      expect(items.map((i) => i.title).toList(), ['A', 'B']);

      await repository.updateItem(a.copyWith(notes: 'annual service'));
      items = await repository.getByTripId(testTrip.id);
      expect(items.first.notes, 'annual service');

      await repository.toggleDone(a.id, isDone: true);
      items = await repository.getByTripId(testTrip.id);
      expect(items.first.isDone, isTrue);
      expect(items.first.completedAt, isNotNull);

      await repository.toggleDone(a.id, isDone: false);
      items = await repository.getByTripId(testTrip.id);
      expect(items.first.isDone, isFalse);
      expect(items.first.completedAt, isNull);

      await repository.deleteItem(a.id);
      expect(await repository.getByTripId(testTrip.id), hasLength(1));
    });
  });

  group('applyTemplate', () {
    late ChecklistTemplate template;

    setUp(() async {
      template = await templateRepository.createTemplate(
        ChecklistTemplate(
          id: '',
          name: 'Prep',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await templateRepository.saveItems(template.id, [
        ChecklistTemplateItem(
          id: '',
          templateId: template.id,
          title: 'Book flights',
          category: 'Bookings',
          dueOffsetDays: 60,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        ChecklistTemplateItem(
          id: '',
          templateId: template.id,
          title: 'Pack wetsuit',
          category: 'Gear',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ]);
    });

    test('copies items resolving offsets to absolute due dates', () async {
      final result = await repository.applyTemplate(
        templateId: template.id,
        trip: testTrip,
      );
      expect(result.added, 2);
      expect(result.skipped, 0);

      final items = await repository.getByTripId(testTrip.id);
      expect(items, hasLength(2));
      final flights = items.firstWhere((i) => i.title == 'Book flights');
      expect(flights.dueDate, tripStart.subtract(const Duration(days: 60)));
      final wetsuit = items.firstWhere((i) => i.title == 'Pack wetsuit');
      expect(wetsuit.dueDate, isNull);
      expect(items.every((i) => !i.isDone), isTrue);
    });

    test('re-apply skips items with matching title and category', () async {
      await repository.applyTemplate(templateId: template.id, trip: testTrip);
      final second = await repository.applyTemplate(
        templateId: template.id,
        trip: testTrip,
      );
      expect(second.added, 0);
      expect(second.skipped, 2);
      expect(await repository.getByTripId(testTrip.id), hasLength(2));
    });

    test('throws StateError when template does not exist', () async {
      await expectLater(
        repository.applyTemplate(templateId: 'missing', trip: testTrip),
        throwsStateError,
      );
      expect(await repository.getByTripId(testTrip.id), isEmpty);
    });
  });

  group('saveAsTemplate', () {
    test('converts absolute due dates back to offsets', () async {
      await repository.createItem(
        item(
          title: 'Book flights',
          category: 'Bookings',
          dueDate: tripStart.subtract(const Duration(days: 60)),
        ),
      );
      await repository.createItem(item(title: 'Pack wetsuit'));

      final tpl = await repository.saveAsTemplate(
        tripId: testTrip.id,
        tripStartDate: testTrip.startDate,
        name: 'My prep',
      );
      final items = await templateRepository.getItemsForTemplate(tpl.id);
      expect(items, hasLength(2));
      final flights = items.firstWhere((i) => i.title == 'Book flights');
      expect(flights.dueOffsetDays, 60);
      final wetsuit = items.firstWhere((i) => i.title == 'Pack wetsuit');
      expect(wetsuit.dueOffsetDays, isNull);
    });
  });

  group('progress and cascade', () {
    test('getProgress counts done vs total', () async {
      final a = await repository.createItem(item(title: 'A'));
      await repository.createItem(item(title: 'B'));
      await repository.toggleDone(a.id, isDone: true);
      final progress = await repository.getProgress(testTrip.id);
      expect(progress.done, 1);
      expect(progress.total, 2);
    });

    test('deleteByTripId removes all items', () async {
      await repository.createItem(item(title: 'A'));
      await repository.createItem(item(title: 'B'));
      await repository.deleteByTripId(testTrip.id);
      expect(await repository.getByTripId(testTrip.id), isEmpty);
    });
  });
}
