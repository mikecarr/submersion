import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:submersion/core/buoyancy/buoyancy_twin.dart';
import 'package:submersion/core/utils/unit_formatter.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Net-buoyancy-versus-time line chart. Buoyant (positive) fill above the
/// zero line, heavy (negative) fill below it; tapping a point reveals the
/// term breakdown at that moment.
class BuoyancyChart extends StatelessWidget {
  final BuoyancyTwinResult result;
  final UnitFormatter units;
  final double height;

  const BuoyancyChart({
    super.key,
    required this.result,
    required this.units,
    this.height = 180,
  });

  /// Chart points in (minutes, converted-net) space, with non-finite values
  /// dropped so a NaN can never reach fl_chart (a known crash source).
  static List<FlSpot> spotsFor(List<TwinSample> samples, UnitFormatter units) {
    final spots = <FlSpot>[];
    for (final s in samples) {
      final y = units.convertWeight(s.netKg);
      if (!s.netKg.isFinite || !y.isFinite) continue;
      spots.add(FlSpot(s.timestamp / 60.0, y));
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    if (result.samples.length < 2) return const SizedBox.shrink();
    final spots = spotsFor(result.samples, units);
    if (spots.length < 2) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final buoyant = theme.colorScheme.primary;
    final heavy = theme.colorScheme.error;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touched) => touched.map((spot) {
                final sample = result.samples[spot.spotIndex];
                final staticLead =
                    sample.netKg - sample.suitKg - sample.tanksKg;
                return LineTooltipItem(
                  '${units.formatDepth(sample.depthM)}  '
                  '${_min(sample.timestamp)}\n'
                  '${context.l10n.buoyancy_chartNet}: '
                  '${units.formatWeight(sample.netKg)}\n'
                  '${context.l10n.buoyancy_suitTerm}: '
                  '${units.formatWeight(sample.suitKg)}   '
                  '${context.l10n.diveDetailSection_tanks_name}: '
                  '${units.formatWeight(sample.tanksKg)}   '
                  '${context.l10n.buoyancy_chartRig}: '
                  '${units.formatWeight(staticLead)}',
                  TextStyle(
                    color: theme.colorScheme.onInverseSurface,
                    fontSize: 11,
                  ),
                );
              }).toList(),
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) => Text(
                  value.toStringAsFixed(0),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    value.toStringAsFixed(0),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y: 0,
                color: theme.colorScheme.outline,
                strokeWidth: 1,
                dashArray: [4, 4],
              ),
            ],
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              color: buoyant,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              // belowBarData with cutOffY 0 tints the buoyant (positive)
              // region; aboveBarData tints the heavy (negative) region.
              belowBarData: BarAreaData(
                show: true,
                applyCutOffY: true,
                cutOffY: 0,
                color: buoyant.withValues(alpha: 0.12),
              ),
              aboveBarData: BarAreaData(
                show: true,
                applyCutOffY: true,
                cutOffY: 0,
                color: heavy.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _min(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }
}
