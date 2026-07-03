import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/checklists/domain/entities/trip_checklist_item.dart';
import 'package:submersion/features/checklists/presentation/providers/checklist_providers.dart';
import 'package:submersion/features/checklists/presentation/widgets/trip_checklist_section.dart';
import 'package:submersion/features/trips/domain/entities/trip.dart';

import '../../../../helpers/test_app.dart';

Trip _trip({required bool upcoming}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final start = upcoming
      ? today.add(const Duration(days: 10))
      : today.subtract(const Duration(days: 20));
  return Trip(
    id: 't1',
    name: 'Test',
    startDate: start,
    endDate: start.add(const Duration(days: 7)),
    createdAt: today,
    updatedAt: today,
  );
}

TripChecklistItem _item({
  String id = 'i1',
  String title = 'Service regulator',
  String? category,
  bool isDone = false,
  DateTime? dueDate,
}) => TripChecklistItem(
  id: id,
  tripId: 't1',
  title: title,
  category: category,
  isDone: isDone,
  dueDate: dueDate,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  testWidgets('groups items by category and shows checkboxes', (tester) async {
    await tester.pumpWidget(
      testApp(
        overrides: [
          tripChecklistProvider('t1').overrideWith(
            (ref) async => [
              _item(id: 'i1', title: 'Service regulator', category: 'Gear'),
              _item(id: 'i2', title: 'Book flights', category: 'Bookings'),
              _item(id: 'i3', title: 'Passport check'),
            ],
          ),
        ],
        child: SingleChildScrollView(
          child: TripChecklistSection(trip: _trip(upcoming: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gear'), findsOneWidget);
    expect(find.text('Bookings'), findsOneWidget);
    expect(find.text('Service regulator'), findsOneWidget);
    expect(find.text('Passport check'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(3));
  });

  testWidgets('shows overdue chip only for upcoming trips', (tester) async {
    final overdue = _item(
      dueDate: DateTime.now().subtract(const Duration(days: 3)),
    );
    await tester.pumpWidget(
      testApp(
        overrides: [
          tripChecklistProvider('t1').overrideWith((ref) async => [overdue]),
        ],
        child: SingleChildScrollView(
          child: TripChecklistSection(trip: _trip(upcoming: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Overdue'), findsOneWidget);

    await tester.pumpWidget(
      testApp(
        overrides: [
          tripChecklistProvider('t1').overrideWith((ref) async => [overdue]),
        ],
        child: SingleChildScrollView(
          child: TripChecklistSection(trip: _trip(upcoming: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Overdue'), findsNothing);
  });

  testWidgets('empty upcoming trip shows planning invitation', (tester) async {
    await tester.pumpWidget(
      testApp(
        overrides: [
          tripChecklistProvider('t1').overrideWith((ref) async => []),
        ],
        child: SingleChildScrollView(
          child: TripChecklistSection(trip: _trip(upcoming: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Plan your trip - add to-dos or apply a template'),
      findsOneWidget,
    );
  });
}
