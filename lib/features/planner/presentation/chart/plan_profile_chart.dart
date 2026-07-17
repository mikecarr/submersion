import 'package:flutter/material.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/core/utils/unit_formatter.dart';
import 'package:submersion/features/dive_planner/presentation/providers/dive_planner_providers.dart';
import 'package:submersion/features/dive_planner/presentation/widgets/simple_plan_dialog.dart';
import 'package:submersion/features/planner/presentation/chart/plan_chart_backdrop_painter.dart';
import 'package:submersion/features/planner/presentation/chart/plan_chart_geometry.dart';
import 'package:submersion/features/planner/presentation/chart/plan_chart_palette.dart';
import 'package:submersion/features/planner/presentation/chart/plan_chart_series_painter.dart';
import 'package:submersion/features/planner/presentation/providers/plan_canvas_providers.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// The Precision Instrument plan chart: three painter layers split by repaint
/// frequency (backdrop / series / overlay), a scrub readout, and gesture
/// handling for hover-scrub and tap-to-select. Pure consumer of the canvas
/// providers - all data flow is unchanged from the fl_chart predecessor.
class PlanProfileChart extends ConsumerWidget {
  const PlanProfileChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref.watch(planCanvasSeriesProvider);
    final ghost = ref.watch(deviationGhostSeriesProvider);
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final units = UnitFormatter(settings);
    final palette = PlanChartPalette.of(theme);

    if (series.isEmpty) return _EmptyState(theme: theme);

    final maxTime =
        ghost != null && ghost.maxTimeSeconds > series.maxTimeSeconds
        ? ghost.maxTimeSeconds
        : series.maxTimeSeconds;
    final maxDepth = ghost != null && ghost.maxDepth > series.maxDepth
        ? ghost.maxDepth
        : series.maxDepth;
    final labelStyle =
        theme.textTheme.labelSmall ?? const TextStyle(fontSize: 10);
    final tagStyle = (theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
      fontSize: 9,
      fontWeight: FontWeight.w600,
    );
    final direction = Directionality.of(context);

    final stopTagLabels = [
      for (final marker in series.stopLabels)
        "${units.formatDepth(marker.depth, decimals: 0)} "
            "${marker.durationSeconds ~/ 60}'",
    ];
    final meanDepthLabel = context.l10n.plannerCanvas_chart_meanDepth(
      units.formatDepth(
        PlanChartGeometry.meanDepthMeters(series.profile),
        decimals: 0,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = PlanChartGeometry(
          size: constraints.biggest,
          maxTimeSeconds: maxTime,
          maxDepthMeters: maxDepth,
          depthUnitScale: units.convertDepth(1),
        );

        void scrubTo(Offset localPosition) {
          ref.read(scrubTimeProvider.notifier).state = geometry.timeAtDx(
            localPosition.dx,
          );
        }

        void clearScrub() => ref.read(scrubTimeProvider.notifier).state = null;

        return MouseRegion(
          onHover: (event) => scrubTo(event.localPosition),
          onExit: (_) => clearScrub(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => scrubTo(details.localPosition),
            onTapUp: (details) {
              final time = geometry.timeAtDx(details.localPosition.dx);
              ref
                  .read(selectedSegmentIdProvider.notifier)
                  .state = segmentIdAtTime(
                ref.read(divePlanNotifierProvider).segments,
                time,
              );
            },
            // DragStartBehavior.start consumes the slop-crossing move, so the
            // start callback is the first scrub sample of a drag.
            onHorizontalDragStart: (details) => scrubTo(details.localPosition),
            onHorizontalDragUpdate: (details) => scrubTo(details.localPosition),
            onHorizontalDragEnd: (_) => clearScrub(),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.backdrop,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        key: const Key('planChartBackdrop'),
                        painter: PlanChartBackdropPainter(
                          geometry: geometry,
                          palette: palette,
                          ceiling: series.ceiling,
                          depthUnitScale: units.convertDepth(1),
                          depthAxisLabel: units.depthSymbol,
                          timeAxisLabel:
                              context.l10n.divePlanner_label_timeAxis,
                          labelStyle: labelStyle,
                          textDirection: direction,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        key: const Key('planChartSeries'),
                        painter: PlanChartSeriesPainter(
                          geometry: geometry,
                          palette: palette,
                          series: series,
                          ghost: ghost,
                          stopTagLabels: stopTagLabels,
                          meanDepthLabel: meanDepthLabel,
                          labelStyle: labelStyle,
                          tagStyle: tagStyle,
                          textDirection: direction,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Consumer(
                      builder: (context, ref, _) {
                        final scrubTime = ref.watch(scrubTimeProvider);
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                key: const Key('planChartOverlay'),
                                painter: PlanChartOverlayPainter(
                                  geometry: geometry,
                                  palette: palette,
                                  scrubX: scrubTime == null
                                      ? null
                                      : geometry.xFor(scrubTime),
                                ),
                              ),
                            ),
                            if (scrubTime != null)
                              Positioned(
                                top: 12,
                                left: PlanChartGeometry.leftGutter + 4,
                                child: _ScrubReadout(
                                  runtimeSeconds: scrubTime,
                                  depthMeters: series.depthAt(scrubTime),
                                  units: units,
                                  palette: palette,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Scrub cursor layer; repaints per pointer event without touching the
/// series or backdrop layers.
class PlanChartOverlayPainter extends CustomPainter {
  final PlanChartGeometry geometry;
  final PlanChartPalette palette;
  final double? scrubX;

  const PlanChartOverlayPainter({
    required this.geometry,
    required this.palette,
    required this.scrubX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final x = scrubX;
    if (x == null) return;
    final plot = geometry.plotRect;
    canvas.drawLine(
      Offset(x, plot.top),
      Offset(x, plot.bottom),
      Paint()
        ..color = palette.scrubCursor
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(PlanChartOverlayPainter oldDelegate) =>
      oldDelegate.scrubX != scrubX ||
      oldDelegate.geometry != geometry ||
      oldDelegate.palette != palette;
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.show_chart, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            context.l10n.divePlanner_message_noProfile,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.divePlanner_message_addSegmentsForProfile,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const SimplePlanDialog(),
            ),
            icon: const Icon(Icons.auto_awesome),
            label: Text(context.l10n.divePlanner_action_quickPlan),
          ),
        ],
      ),
    );
  }
}

class _ScrubReadout extends ConsumerWidget {
  const _ScrubReadout({
    required this.runtimeSeconds,
    required this.depthMeters,
    required this.units,
    required this.palette,
  });

  final double runtimeSeconds;
  final double depthMeters;
  final UnitFormatter units;
  final PlanChartPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final minutes = (runtimeSeconds / 60).round();
    final bailout = ref.watch(planBailoutProvider);
    var text = context.l10n.plannerCanvas_scrub_readout(
      minutes.toString(),
      units.formatDepth(depthMeters, decimals: 0),
    );
    if (bailout != null) {
      final point = bailout.nearest(runtimeSeconds);
      text +=
          ' · '
          '${context.l10n.plannerCanvas_scrub_bailout('${(point.ttsSeconds / 60).ceil()}')}';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.readoutBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.readoutBorder),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: palette.readoutText,
        ),
      ),
    );
  }
}
