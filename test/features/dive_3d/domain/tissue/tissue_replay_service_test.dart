import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/deco/constants/buhlmann_coefficients.dart';
import 'package:submersion/core/deco/entities/dive_environment.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_chain.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_replay_service.dart';

const _service = TissueReplayService();

// A square-profile dive: descent implied, [minutes] at [depth], then a
// column series at 60 s spacing.
TissueDiveInput squareDive({
  required double depth,
  required int minutes,
  double fN2 = airN2Fraction,
  double fHe = 0.0,
}) {
  final times = <double>[];
  final depths = <double>[];
  for (var m = 0; m <= minutes; m++) {
    times.add((m * 60).toDouble());
    depths.add(depth);
  }
  return TissueDiveInput(
    times: times,
    depths: depths,
    gasLegs: [GasLeg(startSeconds: 0, fN2: fN2, fHe: fHe)],
  );
}

TissueChainInput chain(
  List<TissueDiveInput> dives, {
  List<int> surfaceIntervals = const [],
}) => TissueChainInput(
  dives: dives,
  surfaceIntervalSeconds: surfaceIntervals,
  gfLow: 0.30,
  gfHigh: 0.70,
  environment: DiveEnvironment.standard,
);

void main() {
  test('single air dive loads fast compartments more than slow ones', () {
    final result = _service.replay(chain([squareDive(depth: 30, minutes: 20)]));
    expect(result.columnCount, 21);
    final last = result.columnCount - 1;
    // Compartment 1 (fastest) is more supersaturated than compartment 16.
    expect(result.gradient(last, 0), greaterThan(result.gradient(last, 15)));
    // Loadings are positive and finite.
    expect(result.combined(last, 0), greaterThan(0));
    expect(result.maxLoadingBar, greaterThan(0));
    expect(result.hasHelium, isFalse);
  });

  test('controlling compartment is a valid index', () {
    final result = _service.replay(chain([squareDive(depth: 30, minutes: 20)]));
    for (final c in result.controlling) {
      expect(c, inInclusiveRange(0, 15));
    }
  });

  test('a surface interval off-gasses fast compartments faster', () {
    final result = _service.replay(
      chain(
        [squareDive(depth: 30, minutes: 20), squareDive(depth: 10, minutes: 5)],
        surfaceIntervals: const [3600], // 1 hour
      ),
    );
    // Seam recorded; surface columns present.
    expect(result.seamColumns, isNotEmpty);
    final surfaceCols = [
      for (var c = 0; c < result.columnCount; c++)
        if (result.isSurface[c]) c,
    ];
    expect(surfaceCols, isNotEmpty);
    final firstSurface = surfaceCols.first;
    final lastSurface = surfaceCols.last;
    // Over the interval, the fast compartment drains a larger fraction than
    // the slow one.
    final fastDrop =
        result.combined(firstSurface, 0) - result.combined(lastSurface, 0);
    final slowDrop =
        result.combined(firstSurface, 15) - result.combined(lastSurface, 15);
    expect(fastDrop, greaterThan(slowDrop));
  });

  test('helium gas produces helium loading', () {
    final result = _service.replay(
      chain([squareDive(depth: 40, minutes: 15, fN2: 0.45, fHe: 0.35)]),
    );
    expect(result.hasHelium, isTrue);
    final last = result.columnCount - 1;
    expect(result.loadingHe(last, 0), greaterThan(0));
  });

  test('deeper dive loads tissues more than a shallow one', () {
    final deep = _service.replay(chain([squareDive(depth: 40, minutes: 20)]));
    final shallow = _service.replay(
      chain([squareDive(depth: 10, minutes: 20)]),
    );
    final deepLast = deep.columnCount - 1;
    final shallowLast = shallow.columnCount - 1;
    expect(
      deep.combined(deepLast, 0),
      greaterThan(shallow.combined(shallowLast, 0)),
    );
  });
}
