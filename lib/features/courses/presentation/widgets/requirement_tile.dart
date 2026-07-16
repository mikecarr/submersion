import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:submersion/l10n/l10n_extension.dart';
import 'package:submersion/features/courses/domain/entities/course_progress.dart';
import 'package:submersion/features/courses/domain/entities/course_requirement.dart';
import 'package:submersion/features/courses/presentation/providers/course_requirement_providers.dart';

/// One requirement row: a checkbox for checklist items, a progress count
/// plus expandable credited-dive list for dive requirements. Unsatisfied
/// dive requirements offer suggestion chips (one tap credits the dive).
class RequirementTile extends ConsumerWidget {
  const RequirementTile({
    super.key,
    required this.progress,
    required this.suggestions,
  });

  final CourseRequirementProgress progress;
  final List<RequirementDiveSummary> suggestions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requirement = progress.requirement;
    if (requirement.kind == RequirementKind.checklist) {
      return CheckboxListTile(
        value: requirement.completedAt != null,
        onChanged: (checked) {
          ref
              .read(courseRequirementRepositoryProvider)
              .setChecklistComplete(requirement.id, checked ?? false);
        },
        title: Text(requirement.name),
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
      );
    }
    return _DiveRequirementTile(progress: progress, suggestions: suggestions);
  }
}

class _DiveRequirementTile extends ConsumerWidget {
  const _DiveRequirementTile({
    required this.progress,
    required this.suggestions,
  });

  final CourseRequirementProgress progress;
  final List<RequirementDiveSummary> suggestions;

  String _diveLabel(RequirementDiveSummary dive) {
    final number = dive.diveNumber != null ? '#${dive.diveNumber}' : '';
    final date = DateFormat.MMMd().format(dive.dateTime);
    final site = dive.siteName;
    return [
      number,
      date,
      if (site != null) site,
    ].where((part) => part.isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requirement = progress.requirement;
    final theme = Theme.of(context);
    final satisfied = progress.isSatisfied;

    return ExpansionTile(
      leading: satisfied
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : Icon(
              Icons.radio_button_unchecked,
              color: theme.colorScheme.outline,
            ),
      title: Text(requirement.name),
      subtitle: Text(
        context.l10n.courses_requirement_diveProgress(
          progress.creditCount,
          requirement.targetCount,
        ),
        style: theme.textTheme.bodySmall,
      ),
      dense: true,
      children: [
        for (final dive in progress.linkedDives)
          ListTile(
            dense: true,
            leading: const Icon(Icons.link, size: 18),
            title: Text(_diveLabel(dive)),
            trailing: IconButton(
              tooltip: context.l10n.courses_action_unlinkDive,
              icon: const Icon(Icons.link_off, size: 18),
              onPressed: () {
                ref
                    .read(courseRequirementRepositoryProvider)
                    .unlinkDive(
                      requirementId: requirement.id,
                      diveId: dive.diveId,
                    );
              },
            ),
          ),
        if (!satisfied && suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.courses_requirement_suggestions,
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final dive in suggestions)
                      ActionChip(
                        label: Text(_diveLabel(dive)),
                        onPressed: () {
                          ref
                              .read(courseRequirementRepositoryProvider)
                              .linkDive(
                                requirementId: requirement.id,
                                diveId: dive.diveId,
                              );
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
