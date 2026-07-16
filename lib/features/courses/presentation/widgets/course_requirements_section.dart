import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:submersion/l10n/l10n_extension.dart';
import 'package:submersion/features/courses/presentation/providers/course_requirement_providers.dart';
import 'package:submersion/features/courses/presentation/widgets/requirement_tile.dart';

/// The requirement tracker card on the course detail page: overall progress
/// header, one tile per requirement, and empty-state actions.
class CourseRequirementsSection extends ConsumerWidget {
  const CourseRequirementsSection({super.key, required this.courseId});

  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync = ref.watch(courseProgressProvider(courseId));
    final suggestionsAsync = ref.watch(suggestedDivesProvider(courseId));
    final theme = Theme.of(context);

    // AsyncValue.value keeps prior data during reloads (#429 flicker rule).
    final progress = progressAsync.value;
    if (progress == null) {
      return const SizedBox.shrink();
    }
    final suggestions = suggestionsAsync.value ?? const [];

    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.checklist,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.courses_section_requirements,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (progress.totalCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.courses_requirements_progress(
                  progress.satisfiedCount,
                  progress.totalCount,
                ),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: progress.satisfiedCount / progress.totalCount,
              ),
              const SizedBox(height: 8),
              for (final requirementProgress in progress.requirements)
                RequirementTile(
                  progress: requirementProgress,
                  suggestions: suggestions,
                ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.courses_requirements_empty,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
