import 'package:submersion/features/dive_3d/domain/geometry/scene_bounds.dart';
import 'package:submersion/features/dive_3d/domain/scene_3d.dart';
import 'package:submersion/features/dive_3d/domain/tissue/chain_time_axis.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_replay_result.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_surface_builder.dart';

/// Assembles the tissue-landscape [Scene3d] from a replay result. Pure and
/// isolate-friendly; reuses the shared renderer via Scene3d. In %M-value
/// mode it includes a red danger plane at the M-value limit and the dive's
/// depth profile for context, so the surface is readable as "how close each
/// tissue got to its deco limit, and when".
class TissueGeometryService {
  static const double _heliumOverlayOpacity = 0.55;

  const TissueGeometryService();

  Scene3d build(
    TissueReplayResult result, {
    required TissueGas gas,
    required TissueColorMode colorMode,
    bool splitHelium = false,
  }) {
    final axis = ChainTimeAxis(
      diveDurations: result.diveDurations,
      surfaceIntervals: result.surfaceIntervals,
    );
    final bounds = SceneBounds(
      durationSeconds: result.totalClockSeconds,
      maxDepthMeters: 1,
      sceneMinY: -TissueSurfaceBuilder.depthContextHeight,
      sceneMaxY: TissueSurfaceBuilder.referenceHeight * 1.35,
    );

    final layers = <SceneLayer>[];

    // Depth profile of the dive, for spatial context under the surface.
    layers.add(
      SceneLayer(TissueSurfaceBuilder.depthContext(result: result, axis: axis)),
    );

    if (splitHelium && result.hasHelium) {
      layers.add(
        SceneLayer(
          TissueSurfaceBuilder.buildSurface(
            result: result,
            axis: axis,
            gas: TissueGas.n2,
            colorMode: colorMode,
          ),
        ),
      );
      layers.add(
        SceneLayer(
          TissueSurfaceBuilder.buildSurface(
            result: result,
            axis: axis,
            gas: TissueGas.he,
            colorMode: colorMode,
            opacity: _heliumOverlayOpacity,
          ),
        ),
      );
    } else {
      layers.add(
        SceneLayer(
          TissueSurfaceBuilder.buildSurface(
            result: result,
            axis: axis,
            gas: gas,
            colorMode: colorMode,
          ),
        ),
      );
    }

    // The M-value limit plane (only meaningful when height encodes %M).
    if (colorMode == TissueColorMode.mValue) {
      layers.add(SceneLayer(TissueSurfaceBuilder.dangerPlane(axis: axis)));
    }

    return Scene3d(
      layers: layers,
      markers: const [],
      bounds: bounds,
      scrubPath: TissueSurfaceBuilder.scrubPath(
        result: result,
        axis: axis,
        gas: gas,
        colorMode: colorMode,
      ),
    );
  }
}
