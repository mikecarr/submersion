import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/checklists/data/repositories/trip_checklist_repository.dart';
import 'package:submersion/features/checklists/domain/entities/checklist_template.dart';
import 'package:submersion/features/checklists/domain/entities/trip_checklist_item.dart';
import 'package:submersion/features/checklists/presentation/providers/checklist_providers.dart';
import 'package:submersion/features/checklists/presentation/widgets/apply_template_sheet.dart';
import 'package:submersion/features/trips/domain/entities/trip.dart';

import '../../../../helpers/test_app.dart';

Trip _trip() => Trip(
  id: 't1',
  name: 'Test',
  startDate: DateTime.now().add(const Duration(days: 10)),
  endDate: DateTime.now().add(const Duration(days: 17)),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

/// Fake repository used to drive the confirm-append flow without a real
/// database: [getByTripId] reports pre-seeded items so the sheet's
/// duplicate-count preview has something to compute, and [applyTemplate]
/// records whether/how many times it was actually invoked so the test can
/// assert it only runs after the user confirms.
class _FakeTripChecklistRepository extends TripChecklistRepository {
  _FakeTripChecklistRepository({required this.existingItems});

  final List<TripChecklistItem> existingItems;
  int applyCallCount = 0;

  @override
  Future<List<TripChecklistItem>> getByTripId(String tripId) async =>
      existingItems;

  @override
  Future<({int added, int skipped})> applyTemplate({
    required String templateId,
    required Trip trip,
  }) async {
    applyCallCount++;
    return (added: 1, skipped: 1);
  }
}

void main() {
  testWidgets('lists templates with item counts', (tester) async {
    final template = ChecklistTemplate(
      id: 'tpl1',
      name: 'Liveaboard packing',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await tester.pumpWidget(
      testApp(
        overrides: [
          checklistTemplatesProvider.overrideWith((ref) async => [template]),
          checklistTemplateItemsProvider('tpl1').overrideWith(
            (ref) async => [
              ChecklistTemplateItem(
                id: 'x1',
                templateId: 'tpl1',
                title: 'Wetsuit',
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
              ),
            ],
          ),
        ],
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showApplyTemplateSheet(context: context, trip: _trip()),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Apply template'), findsOneWidget);
    expect(find.text('Liveaboard packing'), findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);
  });

  testWidgets('shows empty state when no templates exist', (tester) async {
    await tester.pumpWidget(
      testApp(
        overrides: [checklistTemplatesProvider.overrideWith((ref) async => [])],
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showApplyTemplateSheet(context: context, trip: _trip()),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      find.text('No templates yet. Create them in Settings.'),
      findsOneWidget,
    );
  });

  testWidgets('confirms before appending to a trip that already has items', (
    tester,
  ) async {
    final template = ChecklistTemplate(
      id: 'tpl1',
      name: 'Liveaboard packing',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final fakeRepository = _FakeTripChecklistRepository(
      existingItems: [
        TripChecklistItem(
          id: 'existing1',
          tripId: 't1',
          title: 'Wetsuit',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ],
    );

    await tester.pumpWidget(
      testApp(
        overrides: [
          checklistTemplatesProvider.overrideWith((ref) async => [template]),
          checklistTemplateItemsProvider('tpl1').overrideWith(
            (ref) async => [
              ChecklistTemplateItem(
                id: 'x1',
                templateId: 'tpl1',
                title: 'Wetsuit',
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
              ),
              ChecklistTemplateItem(
                id: 'x2',
                templateId: 'tpl1',
                title: 'Fins',
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
              ),
            ],
          ),
          tripChecklistRepositoryProvider.overrideWithValue(fakeRepository),
        ],
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showApplyTemplateSheet(context: context, trip: _trip()),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Liveaboard packing'));
    await tester.pumpAndSettle();

    // Confirm dialog appears with the computed add/skip counts and apply
    // has not run yet.
    expect(
      find.text('1 items will be added, 1 duplicates skipped.'),
      findsOneWidget,
    );
    expect(fakeRepository.applyCallCount, 0);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(fakeRepository.applyCallCount, 1);
    expect(find.text('1 item added'), findsOneWidget);
  });
}
