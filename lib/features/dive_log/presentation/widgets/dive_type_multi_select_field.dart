import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_types/presentation/providers/dive_type_providers.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Multi-select dive-type field: collapses to a row of chips for the selected
/// types and expands (as an anchored dropdown of checkboxes) to add or remove
/// types. Enforces the at-least-one invariant — the last selected type cannot
/// be unchecked. Custom types are managed on the dedicated dive-types page.
class DiveTypeMultiSelectField extends ConsumerWidget {
  const DiveTypeMultiSelectField({
    super.key,
    required this.selectedTypeIds,
    required this.onChanged,
    this.labelText,
    this.allowEmpty = false,
  });

  /// The currently selected dive-type slugs (>= 1 by invariant).
  final List<String> selectedTypeIds;

  /// Called with the new set whenever the selection changes.
  final ValueChanged<List<String>> onChanged;

  final String? labelText;

  /// When true (bulk-edit mode), the selection may be cleared to empty. The
  /// >= 1 invariant only applies to a single dive's own type set, not to the
  /// "which types to add/remove/replace" selection in bulk mode.
  final bool allowEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typesAsync = ref.watch(diveTypesProvider);
    final label = labelText ?? context.l10n.diveLog_edit_label_diveTypes;

    return typesAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) =>
          Text(context.l10n.diveLog_edit_errorLoadingDiveTypes(e.toString())),
      data: (types) {
        final nameById = {for (final t in types) t.id: t.name};
        String nameOf(String id) =>
            nameById[id] ?? Dive.diveTypeDisplayName(id);

        void toggle(String id, bool selected) {
          final next = [...selectedTypeIds];
          if (selected) {
            if (!next.contains(id)) next.add(id);
          } else {
            next.remove(id);
            // Single-dive editor enforces >= 1; bulk mode allows clearing.
            if (next.isEmpty && !allowEmpty) return;
          }
          onChanged(next);
        }

        return MenuAnchor(
          menuChildren: [
            for (final t in types)
              CheckboxMenuButton(
                value: selectedTypeIds.contains(t.id),
                onChanged: (v) => toggle(t.id, v ?? false),
                child: Text(t.name),
              ),
          ],
          builder: (context, controller, child) {
            return InkWell(
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: label,
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final id in selectedTypeIds)
                      Chip(
                        label: Text(nameOf(id)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
