import 'package:flutter/material.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/checklists/domain/entities/checklist_template.dart';
import 'package:submersion/features/checklists/presentation/providers/checklist_providers.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Create/edit page for a checklist template and its items.
class ChecklistTemplateEditPage extends ConsumerStatefulWidget {
  final String? templateId;

  const ChecklistTemplateEditPage({super.key, this.templateId});

  bool get isEditing => templateId != null;

  @override
  ConsumerState<ChecklistTemplateEditPage> createState() =>
      _ChecklistTemplateEditPageState();
}

class _ChecklistTemplateEditPageState
    extends ConsumerState<ChecklistTemplateEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  List<ChecklistTemplateItem> _items = [];
  ChecklistTemplate? _existing;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final repository = ref.read(checklistTemplateRepositoryProvider);
    final template = await repository.getTemplateById(widget.templateId!);
    final items = await repository.getItemsForTemplate(widget.templateId!);
    if (!mounted) return;
    setState(() {
      _existing = template;
      _nameController.text = template?.name ?? '';
      _descriptionController.text = template?.description ?? '';
      _items = items;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _addOrEditItem({ChecklistTemplateItem? item}) async {
    final result = await _showItemDialog(item: item);
    if (result == null) return;
    setState(() {
      if (item == null) {
        _items = [..._items, result];
      } else {
        _items = [
          for (final existing in _items)
            if (identical(existing, item)) result else existing,
        ];
      }
    });
  }

  Future<ChecklistTemplateItem?> _showItemDialog({
    ChecklistTemplateItem? item,
  }) {
    final titleController = TextEditingController(text: item?.title ?? '');
    final categoryController = TextEditingController(
      text: item?.category ?? '',
    );
    final notesController = TextEditingController(text: item?.notes ?? '');
    final offsetController = TextEditingController(
      text: item?.dueOffsetDays?.toString() ?? '',
    );
    final itemFormKey = GlobalKey<FormState>();

    return showDialog<ChecklistTemplateItem>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.checklists_template_addItem),
        content: Form(
          key: itemFormKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: titleController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: context.l10n.checklists_item_titleLabel,
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? context.l10n.checklists_item_titleRequired
                      : null,
                ),
                TextFormField(
                  controller: categoryController,
                  decoration: InputDecoration(
                    labelText: context.l10n.checklists_item_categoryLabel,
                  ),
                ),
                TextFormField(
                  controller: notesController,
                  decoration: InputDecoration(
                    labelText: context.l10n.checklists_item_notesLabel,
                  ),
                ),
                TextFormField(
                  controller: offsetController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.l10n.checklists_item_dueOffsetLabel,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.common_action_cancel),
          ),
          FilledButton(
            onPressed: () {
              if (!itemFormKey.currentState!.validate()) return;
              final category = categoryController.text.trim();
              Navigator.of(context).pop(
                ChecklistTemplateItem(
                  id: item?.id ?? '',
                  templateId: widget.templateId ?? '',
                  title: titleController.text.trim(),
                  category: category.isEmpty ? null : category,
                  notes: notesController.text.trim(),
                  dueOffsetDays: int.tryParse(offsetController.text.trim()),
                  sortOrder: item?.sortOrder ?? _items.length,
                  createdAt: item?.createdAt ?? DateTime.now(),
                  updatedAt: DateTime.now(),
                ),
              );
            },
            child: Text(context.l10n.common_action_ok),
          ),
        ],
      ),
    ).whenComplete(() {
      titleController.dispose();
      categoryController.dispose();
      notesController.dispose();
      offsetController.dispose();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repository = ref.read(checklistTemplateRepositoryProvider);
    final navigator = Navigator.of(context);
    String templateId;
    if (_existing == null) {
      final created = await repository.createTemplate(
        ChecklistTemplate(
          id: '',
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      templateId = created.id;
    } else {
      await repository.updateTemplate(
        _existing!.copyWith(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
        ),
      );
      templateId = _existing!.id;
    }
    await repository.saveItems(templateId, [
      for (final item in _items) item.copyWith(templateId: templateId),
    ]);
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.checklists_templates_pageTitle),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: Text(context.l10n.common_action_save),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: context.l10n.checklists_template_nameLabel,
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? context.l10n.checklists_template_nameRequired
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: InputDecoration(
                      labelText:
                          context.l10n.checklists_template_descriptionLabel,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    context.l10n.checklists_template_itemsHeader,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: true,
                    onReorderItem: (oldIndex, newIndex) {
                      setState(() {
                        final items = [..._items];
                        final item = items.removeAt(oldIndex);
                        items.insert(newIndex, item);
                        _items = items;
                      });
                    },
                    children: [
                      for (var i = 0; i < _items.length; i++)
                        ListTile(
                          key: ValueKey('item-$i-${_items[i].title}'),
                          title: Text(_items[i].title),
                          subtitle: _items[i].category == null
                              ? null
                              : Text(_items[i].category!),
                          leading: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setState(
                              () => _items = [..._items]..removeAt(i),
                            ),
                          ),
                          onTap: () => _addOrEditItem(item: _items[i]),
                        ),
                    ],
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(context.l10n.checklists_template_addItem),
                    onPressed: () => _addOrEditItem(),
                  ),
                ],
              ),
            ),
    );
  }
}
