import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_3d/domain/geometry/scene_bounds.dart';
import 'package:submersion/features/dive_3d/domain/tissue/chain_time_axis.dart';

void main() {
  test('compresses surface intervals to a fixed seam width', () {
    // Two 30-min dives with a huge 3-hour interval between them.
    final axis = ChainTimeAxis(
      diveDurations: const [1800, 1800],
      surfaceIntervals: const [10800],
    );
    // Each dive occupies (1 - seamFraction) / 2 of the span; the seam is
    // fixed regardless of the 3-hour real duration.
    final firstDiveWidth = axis.xOf(1800) - axis.xOf(0);
    final secondDiveWidth =
        axis.xOf(1800 + 10800 + 1800) - axis.xOf(1800 + 10800);
    expect(firstDiveWidth, closeTo(secondDiveWidth, 1e-6));
    final seamWidth = axis.xOf(1800 + 10800) - axis.xOf(1800);
    expect(
      seamWidth,
      closeTo(ChainTimeAxis.seamFraction * SceneBounds.xSpan, 1e-6),
    );
    expect(firstDiveWidth, greaterThan(seamWidth));
  });

  test('is monotonic and spans the full width', () {
    final axis = ChainTimeAxis(
      diveDurations: const [1200, 2400],
      surfaceIntervals: const [3600],
    );
    expect(axis.xOf(0), closeTo(0, 1e-9));
    expect(axis.xOf(axis.totalClockSeconds), closeTo(SceneBounds.xSpan, 1e-6));
    double prev = -1;
    for (var t = 0.0; t <= axis.totalClockSeconds; t += 60) {
      final x = axis.xOf(t);
      expect(x, greaterThanOrEqualTo(prev));
      prev = x;
    }
  });

  test('single dive maps linearly across the full width', () {
    final axis = ChainTimeAxis(
      diveDurations: const [1200],
      surfaceIntervals: const [],
    );
    expect(axis.xOf(600), closeTo(SceneBounds.xSpan / 2, 1e-6));
    expect(axis.seamXs, isEmpty);
  });
}
