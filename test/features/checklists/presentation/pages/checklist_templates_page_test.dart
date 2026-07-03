import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/checklists/domain/entities/checklist_template.dart';
import 'package:submersion/features/checklists/presentation/pages/checklist_templates_page.dart';
import 'package:submersion/features/checklists/presentation/providers/checklist_providers.dart';

import '../../../../helpers/test_app.dart';

void main() {
  testWidgets('lists templates with item counts', (tester) async {
    await tester.pumpWidget(
      testApp(
        overrides: [
          checklistTemplatesProvider.overrideWith(
            (ref) async => [
              ChecklistTemplate(
                id: 'tpl1',
                name: 'Liveaboard packing',
                description: 'Everything for a week aboard',
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
              ),
            ],
          ),
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
        child: const ChecklistTemplatesPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Checklist Templates'), findsOneWidget);
    expect(find.text('Liveaboard packing'), findsOneWidget);
  });

  testWidgets('shows empty state', (tester) async {
    await tester.pumpWidget(
      testApp(
        overrides: [checklistTemplatesProvider.overrideWith((ref) async => [])],
        child: const ChecklistTemplatesPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No templates yet'), findsOneWidget);
  });
}
