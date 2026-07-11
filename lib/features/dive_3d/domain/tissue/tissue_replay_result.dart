import 'dart:typed_data';

/// Per-column tissue state across a replayed dive chain. Flat typed arrays
/// (isolate-transferable). Column c, compartment k is index `c * 16 + k`.
class TissueReplayResult {
  static const int compartmentCount = 16;

  /// Chain-clock seconds per column (monotonic across dives + intervals).
  final List<double> times;

  /// Depth (m) per column; 0 during surface intervals.
  final List<double> depths;

  /// True when the column belongs to a surface interval.
  final List<bool> isSurface;

  /// N2 and He tension per (column, compartment), bar absolute.
  final Float32List loadingsN2;
  final Float32List loadingsHe;

  /// Supersaturation gradient fraction per (column, compartment): 0 at
  /// ambient, 1 at the raw M-value.
  final Float32List gradientFactors;

  /// Index (0-15) of the highest-gradient compartment per column.
  final Uint8List controlling;

  /// Column indices at which a surface interval begins (seam markers).
  final List<int> seamColumns;

  final bool hasHelium;
  final double maxLoadingBar;
  final double totalClockSeconds;

  /// Per-dive durations (s) and inter-dive surface intervals (s) - enough
  /// to rebuild the seam-compressed [ChainTimeAxis] without the input.
  final List<int> diveDurations;
  final List<int> surfaceIntervals;

  const TissueReplayResult({
    required this.times,
    required this.depths,
    required this.isSurface,
    required this.loadingsN2,
    required this.loadingsHe,
    required this.gradientFactors,
    required this.controlling,
    required this.seamColumns,
    required this.hasHelium,
    required this.maxLoadingBar,
    required this.totalClockSeconds,
    required this.diveDurations,
    required this.surfaceIntervals,
  });

  int get columnCount => times.length;

  double loadingN2(int column, int compartment) =>
      loadingsN2[column * compartmentCount + compartment];
  double loadingHe(int column, int compartment) =>
      loadingsHe[column * compartmentCount + compartment];
  double combined(int column, int compartment) =>
      loadingN2(column, compartment) + loadingHe(column, compartment);
  double gradient(int column, int compartment) =>
      gradientFactors[column * compartmentCount + compartment];
}
