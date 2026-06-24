import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_log/presentation/widgets/fl_spot_cache.dart';

void main() {
  test('returns the same instance on a key hit (no rebuild)', () {
    final cache = FlSpotCache();
    var builds = 0;
    List<FlSpot> build() {
      builds++;
      return [const FlSpot(0, 0)];
    }

    final a = cache.spots('depth', build);
    final b = cache.spots('depth', build);
    expect(identical(a, b), isTrue);
    expect(builds, 1);
  });

  test(
    'invalidate(newSignature) forces a rebuild; same signature does not',
    () {
      final cache = FlSpotCache();
      var builds = 0;
      List<FlSpot> build() {
        builds++;
        return [const FlSpot(0, 0)];
      }

      cache.invalidate('sigA');
      cache.spots('depth', build);
      cache.invalidate('sigA'); // unchanged -> keep cache
      cache.spots('depth', build);
      expect(builds, 1);

      cache.invalidate('sigB'); // changed -> drop cache
      cache.spots('depth', build);
      expect(builds, 2);
    },
  );

  test('distinct keys are cached independently', () {
    final cache = FlSpotCache();
    final depth = cache.spots('depth', () => [const FlSpot(0, 0)]);
    final temp = cache.spots('temp', () => [const FlSpot(1, 1)]);
    expect(identical(cache.spots('depth', () => []), depth), isTrue);
    expect(identical(cache.spots('temp', () => []), temp), isTrue);
  });
}
