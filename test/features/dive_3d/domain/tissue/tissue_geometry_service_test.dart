import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/deco/entities/dive_environment.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_chain.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_geometry_service.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_replay_result.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_replay_service.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_surface_builder.dart';

TissueReplayResult replay({double fHe = 0.0}) {
  final times = [for (var m = 0; m <= 15; m++) (m * 60).toDouble()];
  final depths = [for (var m = 0; m <= 15; m++) 30.0];
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

void main() {
  const service = TissueGeometryService();

  test('single surface + ridge layers, scene Y range covers the surface', () {
    final scene = service.build(
      replay(),
      gas: TissueGas.combined,
      colorMode: TissueColorMode.mValue,
    );
    // surface + controlling ridge.
    expect(scene.layers.length, 2);
    expect(scene.bounds.sceneMinY, 0);
    expect(scene.bounds.sceneMaxY, TissueSurfaceBuilder.tissueHeight);
    expect(scene.scrubPath, isNotNull);
    expect(scene.markers, isEmpty);
  });

  test('helium split adds a second (translucent) surface only with He', () {
    final withHe = service.build(
      replay(fHe: 0.35),
      gas: TissueGas.combined,
      colorMode: TissueColorMode.mValue,
      splitHelium: true,
    );
    // n2 surface + he surface + ridge.
    expect(withHe.layers.length, 3);
    expect(withHe.layers[1].mesh.opacity, lessThan(1.0));

    final airSplit = service.build(
      replay(),
      gas: TissueGas.combined,
      colorMode: TissueColorMode.mValue,
      splitHelium: true,
    );
    // No helium in an air dive -> falls back to the single surface.
    expect(airSplit.layers.length, 2);
  });
}
