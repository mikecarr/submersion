/// Normalizes any dive into a fixed-size scene box so a 30 min / 18 m dive
/// and a 4 h / 100 m dive both fill the viewport with sane proportions.
/// X = run time (0..xSpan), Y = depth (0 at surface, -ySpan at max depth),
/// Z = lateral extrusion.
class SceneBounds {
  final double durationSeconds;
  final double maxDepthMeters;

  static const double xSpan = 10.0;
  static const double ySpan = 6.0;
  static const double zHalfWidth = 0.18;
  static const double zSlabHalfWidth = 1.0;

  const SceneBounds({
    required this.durationSeconds,
    required this.maxDepthMeters,
  });

  double xOf(num seconds) =>
      durationSeconds <= 0 ? 0 : (seconds / durationSeconds) * xSpan;

  double yOf(num meters) =>
      maxDepthMeters <= 0 ? 0 : -(meters / maxDepthMeters) * ySpan;
}
