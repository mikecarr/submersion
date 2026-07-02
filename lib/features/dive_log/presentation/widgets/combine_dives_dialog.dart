import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:submersion/core/utils/unit_formatter.dart';
import 'package:submersion/features/dive_log/data/services/dive_merge_service.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart'
    as domain;
import 'package:submersion/features/dive_log/domain/services/dive_merge_builder.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_providers.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Dialog that classifies the current dive selection and either previews a
/// sequential combine, explains why an overlapping selection can't be
/// combined yet, or reports an error (mixed divers).
///
/// See dive_merge_builder.dart / dive_merge_service.dart for the underlying
/// classification and persistence logic (#449).
class CombineDivesDialog extends ConsumerStatefulWidget {
  const CombineDivesDialog({super.key, required this.diveIds});
  final List<String> diveIds;
  @override
  ConsumerState<CombineDivesDialog> createState() => _CombineDivesDialogState();
}

class _CombineDivesDialogState extends ConsumerState<CombineDivesDialog> {
  List<domain.Dive>? _dives;
  DiveMergeClassification? _classification;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dives = await ref
        .read(diveRepositoryProvider)
        .getDivesByIds(widget.diveIds);
    if (!mounted) return;
    setState(() {
      _dives = dives;
      _classification = const DiveMergeBuilder().classify(dives);
    });
  }

  Future<void> _confirm() async {
    setState(() => _working = true);
    try {
      final outcome = await ref
          .read(diveMergeServiceProvider)
          .apply(widget.diveIds);
      if (mounted) Navigator.of(context).pop(outcome);
    } catch (_) {
      if (mounted) {
        setState(() => _working = false);
        Navigator.of(context).pop(null);
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: switch (_classification) {
          null => const Center(child: CircularProgressIndicator()),
          final MergeSequential seq => _buildPreview(context, seq),
          MergeOverlapping() => _buildOverlapPanel(context),
          MergeInvalid() => _buildErrorPanel(context),
        },
      ),
    );
  }

  Widget _buildPreview(BuildContext context, MergeSequential seq) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final units = UnitFormatter(settings);
    final timePattern = ref.watch(timeFormatProvider).pattern;

    // Pure preview computation -- never persisted. Reusing build() here
    // (rather than re-deriving the merged runtime/depth inline) means the
    // preview and the eventual persisted result can never drift apart.
    final result = const DiveMergeBuilder().build(_dives!);

    final rows = <Widget>[];
    for (var i = 0; i < seq.sortedDives.length; i++) {
      rows.add(_diveRow(context, seq.sortedDives[i], timePattern, units));
      if (i < seq.gaps.length) {
        rows.add(_gapRow(context, seq.gaps[i].duration));
      }
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Icon(Icons.call_merge, color: colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  context.l10n.diveLog_combine_title,
                  style: textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.diveLog_combine_previewIntro(seq.sortedDives.length),
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: rows,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.diveLog_combine_resultSummary(
              _formatDuration(result.mergedDive.runtime ?? Duration.zero),
              units.formatDepth(result.mergedDive.maxDepth),
            ),
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.diveLog_combine_dataNote,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _working
                    ? null
                    : () => Navigator.of(context).pop(null),
                child: Text(context.l10n.common_action_cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _working ? null : _confirm,
                child: Text(context.l10n.diveLog_combine_confirm),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _diveRow(
    BuildContext context,
    domain.Dive dive,
    String timePattern,
    UnitFormatter units,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final timeStr = DateFormat(timePattern).format(dive.effectiveEntryTime);
    final durationStr = dive.effectiveRuntime != null
        ? _formatDuration(dive.effectiveRuntime!)
        : null;
    final label = [
      if (dive.diveNumber != null) '#${dive.diveNumber}',
      timeStr,
      ?durationStr,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(label, style: textTheme.bodyMedium),
    );
  }

  Widget _gapRow(BuildContext context, Duration gapDuration) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        context.l10n.diveLog_combine_gapLabel(_formatDuration(gapDuration)),
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildOverlapPanel(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  context.l10n.diveLog_combine_overlapTitle,
                  style: textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.diveLog_combine_overlapBody,
            style: textTheme.bodyMedium,
          ),
          if (widget.diveIds.length == 2) ...[
            const SizedBox(height: 12),
            Text(
              context.l10n.diveLog_combine_overlapHintTwoDives,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: Text(context.l10n.common_action_close),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorPanel(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Icon(Icons.error_outline, color: colorScheme.error),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  context.l10n.diveLog_combine_title,
                  style: textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.diveLog_combine_mixedDivers,
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: Text(context.l10n.common_action_close),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes < 60) return '${minutes}min';
    final hours = duration.inHours;
    final remaining = minutes - hours * 60;
    return remaining > 0 ? '${hours}h ${remaining}min' : '${hours}h';
  }
}

/// Shows the combine-dives dialog and returns the merge outcome on success,
/// or null on cancel/close/error.
Future<DiveMergeOutcome?> showCombineDivesDialog({
  required BuildContext context,
  required List<String> diveIds,
}) => showDialog<DiveMergeOutcome>(
  context: context,
  builder: (_) => CombineDivesDialog(diveIds: diveIds),
);
