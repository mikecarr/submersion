import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/deco/entities/dive_environment.dart';
import 'package:submersion/features/dive_3d/domain/tissue/chain_time_axis.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_chain.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_replay_result.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_replay_service.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_surface_builder.dart';

TissueReplayResult replayOneDive({double fHe = 0.0}) {
  final times = [for (var m = 0; m <= 20; m++) (m * 60).toDouble()];
  final depths = [for (var m = 0; m <= 20; m++) 30.0];
  return const TissueReplayService().replay(
    TissueChainInput(
      dives: [
        TissueDiveInput(
          times: times,
          depths: depths,
          gasLegs: [GasLeg(startSeconds: 0, fN2: 0.79 - fHe, fHe: fHe)],
        ),
      ],
      surfaceIntervalSeconds: [],
      gfLow: 0.30,
      gfHigh: 0.70,
      environment: DiveEnvironment.standard,
    ),
  );
}

ChainTimeAxis axisFor(TissueReplayResult r) => ChainTimeAxis(
  diveDurations: [r.totalClockSeconds.round()],
  surfaceIntervals: const [],
);

void main() {
  test('surface grid has one vertex per (column, compartment)', () {
    final result = replayOneDive();
    final mesh = TissueSurfaceBuilder.buildSurface(
      result: result,
      axis: axisFor(result),
      gas: TissueGas.combined,
      colorMode: TissueColorMode.mValue,
    );
    expect(mesh.vertexCount, result.columnCount * 16);
    expect(mesh.triangleCount, (result.columnCount - 1) * 15 * 2);
    expect(mesh.colors.every((c) => c.isFinite), isTrue);
  });

  test('height reflects relative loading (loaded > baseline)', () {
    final result = replayOneDive();
    final mesh = TissueSurfaceBuilder.buildSurface(
      result: result,
      axis: axisFor(result),
      gas: TissueGas.combined,
      colorMode: TissueColorMode.absolute,
    );
    // First column, compartment 0 (start, low load) vs last column
    // compartment 0 (loaded): later is higher in Y.
    final firstY = mesh.positions[1];
    final lastColStart = (result.columnCount - 1) * 16 * 3;
    final lastY = mesh.positions[lastColStart + 1];
    expect(lastY, greaterThan(firstY));
  });

  test('controlling ridge has a quad per column gap', () {
    final result = replayOneDive();
    final ridge = TissueSurfaceBuilder.buildControllingRidge(
      result: result,
      axis: axisFor(result),
    )!;
    expect(ridge.triangleCount, (result.columnCount - 1) * 2);
  });

  test('scrub path spans normalized time', () {
    final result = replayOneDive();
    final path = TissueSurfaceBuilder.scrubPath(
      result: result,
      axis: axisFor(result),
    );
    expect(path.normalizedTimes.first, closeTo(0, 1e-9));
    expect(path.normalizedTimes.last, closeTo(1, 1e-9));
    expect(path.positionAt(0.5), isNotNull);
  });

  test('helium gas surface differs from nitrogen surface', () {
    final result = replayOneDive(fHe: 0.35);
    final axis = axisFor(result);
    final n2 = TissueSurfaceBuilder.buildSurface(
      result: result,
      axis: axis,
      gas: TissueGas.n2,
      colorMode: TissueColorMode.absolute,
    );
    final he = TissueSurfaceBuilder.buildSurface(
      result: result,
      axis: axis,
      gas: TissueGas.he,
      colorMode: TissueColorMode.absolute,
    );
    final last = (result.columnCount - 1) * 16 * 3;
    // N2 and He heights at the loaded end differ.
    expect(
      n2.positions[last + 1],
      isNot(closeTo(he.positions[last + 1], 1e-6)),
    );
  });
}
