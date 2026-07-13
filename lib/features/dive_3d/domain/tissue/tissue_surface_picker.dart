import 'dart:ui';

/// Where a compartment sits relative to ambient-equilibrium (the Subsurface
/// convention: 50% = at ambient). Thresholds are half-open.
enum TissueSaturationState { onGassing, equilibrium, offGassing, pastMValue }

TissueSaturationState tissueSaturationStateForPercent(double percent) {
  if (percent < 45) return TissueSaturationState.onGassing;
  if (percent < 55) return TissueSaturationState.equilibrium;
  if (percent <= 100) return TissueSaturationState.offGassing;
  return TissueSaturationState.pastMValue;
}

/// A picked surface vertex: its grid coordinates and where it landed on screen.
class TissuePick {
  final int col;
  final int comp;
  final Offset screenPos;
  const TissuePick({
    required this.col,
    required this.comp,
    required this.screenPos,
  });
}

const double _tiePx = 4.0;

/// Nearest projected surface vertex to [cursor] within [thresholdPx]. On a
/// near-tie (within [_tiePx]) prefers the greater [viewDepths] value so the
/// cursor picks the visible front surface, not a vertex hidden behind it.
/// Returns null if nothing qualifies. [projected]/[viewDepths] are indexed
/// col*compartments + comp.
TissuePick? pickNearestTissueVertex({
  required Offset cursor,
  required List<Offset> projected,
  required List<double> viewDepths,
  required int columns,
  required int compartments,
  double thresholdPx = 20,
}) {
  var bestIndex = -1;
  var bestDist = thresholdPx;
  var bestDepth = double.negativeInfinity;
  for (var i = 0; i < projected.length; i++) {
    final d = (projected[i] - cursor).distance;
    if (d > thresholdPx) continue;
    final better =
        bestIndex < 0 ||
        d < bestDist - _tiePx ||
        ((d - bestDist).abs() <= _tiePx && viewDepths[i] > bestDepth);
    if (better) {
      bestIndex = i;
      bestDist = d < bestDist ? d : bestDist;
      bestDepth = viewDepths[i];
    }
  }
  if (bestIndex < 0) return null;
  return TissuePick(
    col: bestIndex ~/ compartments,
    comp: bestIndex % compartments,
    screenPos: projected[bestIndex],
  );
}
