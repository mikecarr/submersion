import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/checklists/data/repositories/checklist_template_repository.dart';
import 'package:submersion/features/checklists/domain/entities/checklist_template.dart';

import '../../../../helpers/test_database.dart';

void main() {
  late ChecklistTemplateRepository repository;

  ChecklistTemplate template({String name = 'Packing'}) => ChecklistTemplate(
    id: '',
    name: name,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  ChecklistTemplateItem item(
    String templateId, {
    String title = 'Wetsuit',
    int? dueOffsetDays,
    String? category,
  }) => ChecklistTemplateItem(
    id: '',
    templateId: templateId,
    title: title,
    category: category,
    dueOffsetDays: dueOffsetDays,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  setUp(() async {
    await setUpTestDatabase();
    repository = ChecklistTemplateRepository();
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  group('createTemplate / getAllTemplates / getTemplateById', () {
    test('creates with generated id and reads back', () async {
      final created = await repository.createTemplate(template());
      expect(created.id, isNotEmpty);
      final all = await repository.getAllTemplates();
      expect(all, hasLength(1));
      expect(all.first.name, 'Packing');
      final byId = await repository.getTemplateById(created.id);
      expect(byId, isNotNull);
    });

    test('orders templates by name', () async {
      await repository.createTemplate(template(name: 'Zeta'));
      await repository.createTemplate(template(name: 'Alpha'));
      final all = await repository.getAllTemplates();
      expect(all.map((t) => t.name).toList(), ['Alpha', 'Zeta']);
    });
  });

  group('saveItems / getItemsForTemplate', () {
    test('replace-all save assigns sortOrder from list position', () async {
      final tpl = await repository.createTemplate(template());
      await repository.saveItems(tpl.id, [
        item(tpl.id, title: 'B'),
        item(tpl.id, title: 'A', dueOffsetDays: 14, category: 'Gear'),
      ]);
      final items = await repository.getItemsForTemplate(tpl.id);
      expect(items.map((i) => i.title).toList(), ['B', 'A']);
      expect(items[1].dueOffsetDays, 14);
      expect(items[1].category, 'Gear');

      // Re-save with one item: the other is removed.
      await repository.saveItems(tpl.id, [item(tpl.id, title: 'A only')]);
      final after = await repository.getItemsForTemplate(tpl.id);
      expect(after, hasLength(1));
      expect(after.single.title, 'A only');
    });
  });

  group('updateTemplate / deleteTemplate', () {
    test('update changes name, delete removes template and items', () async {
      final tpl = await repository.createTemplate(template());
      await repository.updateTemplate(tpl.copyWith(name: 'Renamed'));
      expect((await repository.getTemplateById(tpl.id))!.name, 'Renamed');

      await repository.saveItems(tpl.id, [item(tpl.id)]);
      await repository.deleteTemplate(tpl.id);
      expect(await repository.getTemplateById(tpl.id), isNull);
      expect(await repository.getItemsForTemplate(tpl.id), isEmpty);
    });
  });
}
