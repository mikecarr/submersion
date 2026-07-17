import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/equipment/domain/entities/equipment_set.dart';
import 'package:submersion/features/equipment/presentation/providers/equipment_set_providers.dart';
import 'package:submersion/features/pre_dive/data/repositories/pre_dive_template_repository.dart';
import 'package:submersion/features/pre_dive/domain/entities/pre_dive_checklist_template.dart';
import 'package:submersion/features/pre_dive/presentation/providers/pre_dive_providers.dart';
import 'package:submersion/features/pre_dive/presentation/widgets/start_session_sheet.dart';

import '../../../../helpers/test_app.dart';

/// Serves canned template items so selecting a template in the sheet can
/// reveal (or not) the equipment-set picker.
class _FakeTemplateRepo implements PreDiveTemplateRepository {
  final Map<String, List<PreDiveChecklistTemplateItem>> itemsByTemplate;

  _FakeTemplateRepo(this.itemsByTemplate);

  @override
  Future<List<PreDiveChecklistTemplateItem>> getItemsForTemplate(
    String templateId,
  ) async => itemsByTemplate[templateId] ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  PreDiveChecklistTemplate template(String id, String name) =>
      PreDiveChecklistTemplate(
        id: id,
        name: name,
        createdAt: now,
        updatedAt: now,
      );

  PreDiveChecklistTemplateItem tItem(String templateId, PreDiveItemType type) =>
      PreDiveChecklistTemplateItem(
        id: '$templateId-i',
        templateId: templateId,
        title: 'T',
        itemType: type,
        createdAt: now,
        updatedAt: now,
      );

  final defaultSet = EquipmentSet(
    id: 'set1',
    name: 'Warm water rig',
    isDefault: true,
    equipmentIds: const ['g1'],
    createdAt: now,
    updatedAt: now,
  );

  Future<void> pumpSheet(WidgetTester tester) async {
    final fakeRepo = _FakeTemplateRepo({
      'plain': [tItem('plain', PreDiveItemType.check)],
      'packing': [tItem('packing', PreDiveItemType.equipmentSet)],
    });
    await tester.pumpWidget(
      testApp(
        overrides: [
          preDiveTemplateRepositoryProvider.overrideWithValue(fakeRepo),
          preDiveTemplatesProvider.overrideWith(
            (ref) async => [
              template('plain', 'BWRAF'),
              template('packing', 'Gear Packing'),
            ],
          ),
          equipmentSetsProvider.overrideWith((ref) async => [defaultSet]),
        ],
        child: Builder(
          builder: (context) => Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => showStartSessionSheet(context, ref),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'equipment picker appears only for equipmentSet-bearing templates',
    (tester) async {
      await pumpSheet(tester);
      expect(find.text('Start pre-dive checklist'), findsOneWidget);
      expect(find.text('Equipment set'), findsNothing);

      // Choose the plain template: still no equipment picker.
      await tester.tap(find.text('Checklist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BWRAF').last);
      await tester.pumpAndSettle();
      expect(find.text('Equipment set'), findsNothing);

      // Choose the packing template: picker appears with the default set
      // pre-selected.
      await tester.tap(find.text('BWRAF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gear Packing').last);
      await tester.pumpAndSettle();
      expect(find.text('Equipment set'), findsOneWidget);
      expect(find.text('Warm water rig'), findsOneWidget);
    },
  );

  testWidgets('Begin disabled until a template is chosen', (tester) async {
    await pumpSheet(tester);
    final begin = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Begin'),
    );
    expect(begin.onPressed, isNull);
  });
}
