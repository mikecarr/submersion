import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/checklists/domain/entities/checklist_template.dart';
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
}
