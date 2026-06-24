import 'package:fl_chart/fl_chart.dart';

/// Memoizes per-curve `FlSpot` lists for the dive profile chart. The cache is
/// dropped whenever the underlying data or units change (a new data signature);
/// within one signature, repeated builds (playback ticks, hover, zoom, legend
/// toggles) are pure cache hits and never reconstruct the spot lists.
class FlSpotCache {
  final Map<String, List<FlSpot>> _cache = {};
  String? _signature;

  /// Drops all cached series if [dataSignature] differs from the last one.
  void invalidate(String dataSignature) {
    if (dataSignature != _signature) {
      _cache.clear();
      _signature = dataSignature;
    }
  }

  /// Returns the cached spots for [key], building once via [build] on a miss.
  List<FlSpot> spots(String key, List<FlSpot> Function() build) {
    return _cache[key] ??= build();
  }
}
