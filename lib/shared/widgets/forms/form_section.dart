import 'package:flutter/material.dart';

import 'package:submersion/l10n/l10n_extension.dart';
import 'package:submersion/shared/widgets/forms/form_style.dart';

/// A collapsible form group: uppercase label outside, tonal rounded surface.
///
/// Three resting states:
/// - expanded: [hero] (optional) + [children] with hairline dividers
/// - collapsed with data: single bar showing [summary]
/// - collapsed and empty: muted [emptyInvitation] bar with a + affordance
///
/// Expansion is owned by the page (smart-collapse defaults live there);
/// pass [onToggle] null for sections that are never collapsible.
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.label,
    required this.expanded,
    required this.onToggle,
    required this.children,
    this.summary,
    this.emptyInvitation,
    this.isEmpty = false,
    this.errorCount = 0,
    this.hero,
  });

  final String label;
  final bool expanded;
  final VoidCallback? onToggle;
  final List<Widget> children;
  final String? summary;
  final String? emptyInvitation;
  final bool isEmpty;
  final int errorCount;
  final Widget? hero;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: FormStyle.labelStyle(context),
                ),
              ),
              if (expanded && onToggle != null)
                InkWell(
                  onTap: onToggle,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.keyboard_arrow_up,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: FormStyle.labelGap),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: expanded ? _buildExpanded(context) : _buildCollapsed(context),
        ),
      ],
    );
  }

  Widget _buildExpanded(BuildContext context) {
    final divider = Divider(
      height: 1,
      thickness: 1,
      color: FormStyle.dividerColor(context),
    );
    final rows = <Widget>[];
    if (hero != null) {
      rows.add(hero!);
      if (children.isNotEmpty) rows.add(divider);
    }
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) rows.add(divider);
    }
    return Material(
      color: FormStyle.groupColor(context),
      borderRadius: BorderRadius.circular(FormStyle.groupRadius),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  Widget _buildCollapsed(BuildContext context) {
    final theme = Theme.of(context);
    final hasError = errorCount > 0;
    final Widget content;
    if (isEmpty) {
      content = Row(
        children: [
          Expanded(
            child: Text(
              emptyInvitation ?? '',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(Icons.add, size: 18, color: theme.colorScheme.primary),
        ],
      );
    } else {
      content = Row(
        children: [
          Expanded(
            child: Text(
              summary ?? '',
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasError) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.warning_amber_rounded,
              size: 16,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 4),
            Text(
              context.l10n.forms_section_issues(errorCount),
              style: theme.textTheme.labelMedium!.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      );
    }
    return Material(
      color: FormStyle.groupColor(context),
      borderRadius: BorderRadius.circular(FormStyle.groupRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Container(
          decoration: hasError
              ? BoxDecoration(
                  border: Border(
                    left: BorderSide(color: theme.colorScheme.error, width: 3),
                  ),
                )
              : null,
          padding: FormStyle.rowPadding,
          child: Semantics(
            button: onToggle != null,
            label: label,
            child: content,
          ),
        ),
      ),
    );
  }
}
