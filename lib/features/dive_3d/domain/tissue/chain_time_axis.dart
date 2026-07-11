import 'package:submersion/features/dive_3d/domain/geometry/scene_bounds.dart';

/// Maps chain-clock seconds to scene X, compressing each surface interval
/// to a fixed narrow seam so dive segments stay legible regardless of how
/// long the divers sat on the boat. Dive spans share the remaining width in
/// proportion to their real durations.
class ChainTimeAxis {
  /// Fraction of [SceneBounds.xSpan] each surface-interval seam occupies.
  static const double seamFraction = 0.04;

  final List<int> diveDurations;
  final List<int> surfaceIntervals; // length diveDurations.length - 1

  // Piecewise breakpoints: clock seconds -> x, one node per segment edge.
  late final List<double> _clockNodes;
  late final List<double> _xNodes;
  late final List<double> seamXs;
  late final double totalClockSeconds;

  ChainTimeAxis({required this.diveDurations, required this.surfaceIntervals}) {
    final seamCount = surfaceIntervals.length;
    final totalDive = diveDurations.fold<int>(0, (a, b) => a + b);
    final diveWidth = totalDive <= 0
        ? 0.0
        : (SceneBounds.xSpan - seamCount * seamFraction * SceneBounds.xSpan);
    const seamWidth = seamFraction * SceneBounds.xSpan;

    _clockNodes = <double>[0];
    _xNodes = <double>[0];
    seamXs = <double>[];
    var clock = 0.0;
    var x = 0.0;
    for (var d = 0; d < diveDurations.length; d++) {
      final dur = diveDurations[d];
      clock += dur;
      x += totalDive <= 0 ? 0.0 : diveWidth * (dur / totalDive);
      _clockNodes.add(clock);
      _xNodes.add(x);
      if (d < seamCount) {
        seamXs.add(x);
        clock += surfaceIntervals[d];
        x += seamWidth;
        _clockNodes.add(clock);
        _xNodes.add(x);
      }
    }
    totalClockSeconds = clock;
  }

  double xOf(double clockSeconds) {
    if (clockSeconds <= 0) return 0;
    if (clockSeconds >= totalClockSeconds) return _xNodes.last;
    var lo = 0, hi = _clockNodes.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      if (_clockNodes[mid] <= clockSeconds) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = _clockNodes[hi] - _clockNodes[lo];
    final f = span <= 0 ? 0.0 : (clockSeconds - _clockNodes[lo]) / span;
    return _xNodes[lo] + (_xNodes[hi] - _xNodes[lo]) * f;
  }
}
