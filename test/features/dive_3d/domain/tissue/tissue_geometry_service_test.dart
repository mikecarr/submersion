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

  test('%M mode: depth context + surface + danger plane', () {
    final scene = service.build(
      replay(),
      gas: TissueGas.combined,
      colorMode: TissueColorMode.mValue,
    );
    // depthContext + surface + dangerPlane.
    expect(scene.layers.length, 3);
    // Scene Y spans below (depth context) and above (danger plane).
    expect(scene.bounds.sceneMinY, lessThan(0));
    expect(
      scene.bounds.sceneMaxY,
      greaterThan(TissueSurfaceBuilder.referenceHeight),
    );
    expect(scene.scrubPath, isNotNull);
    expect(scene.markers, isEmpty);
  });

  test('absolute mode omits the M-value danger plane', () {
    final scene = service.build(
      replay(),
      gas: TissueGas.combined,
      colorMode: TissueColorMode.absolute,
    );
    // depthContext + surface (no danger plane in absolute mode).
    expect(scene.layers.length, 2);
  });

  test('helium split adds a second (translucent) surface only with He', () {
    final withHe = service.build(
      replay(fHe: 0.35),
      gas: TissueGas.combined,
      colorMode: TissueColorMode.mValue,
      splitHelium: true,
    );
    // depthContext + n2 surface + he surface + dangerPlane.
    expect(withHe.layers.length, 4);
    expect(withHe.layers[2].mesh.opacity, lessThan(1.0));

    final airSplit = service.build(
      replay(),
      gas: TissueGas.combined,
      colorMode: TissueColorMode.mValue,
      splitHelium: true,
    );
    // No helium -> single surface: depthContext + surface + dangerPlane.
    expect(airSplit.layers.length, 3);
  });
}
