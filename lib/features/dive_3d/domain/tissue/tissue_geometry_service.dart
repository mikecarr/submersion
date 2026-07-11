import 'package:submersion/features/dive_3d/domain/geometry/scene_bounds.dart';
import 'package:submersion/features/dive_3d/domain/scene_3d.dart';
import 'package:submersion/features/dive_3d/domain/tissue/chain_time_axis.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_replay_result.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_surface_builder.dart';

/// Assembles the tissue-landscape [Scene3d] from a replay result. Pure and
/// isolate-friendly; reuses the shared renderer via Scene3d.
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
      sceneMinY: 0,
      sceneMaxY: TissueSurfaceBuilder.tissueHeight,
    );

    final layers = <SceneLayer>[];
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

    final ridge = TissueSurfaceBuilder.buildControllingRidge(
      result: result,
      axis: axis,
    );
    if (ridge != null) layers.add(SceneLayer(ridge));

    return Scene3d(
      layers: layers,
      markers: const [],
      bounds: bounds,
      scrubPath: TissueSurfaceBuilder.scrubPath(result: result, axis: axis),
    );
  }
}
