import 'dart:typed_data';
import 'dart:ui';

import 'package:submersion/features/dive_3d/domain/career/career_scene_data.dart';
import 'package:submersion/features/dive_3d/domain/geometry/ribbon_builder.dart';
import 'package:submersion/features/dive_3d/domain/geometry/scene_bounds.dart';
import 'package:submersion/features/dive_3d/domain/scene_3d.dart';

/// How career ribbons are colored across the set.
enum CareerColorMode { recency, depth }

/// Builds the career "terrain": one depth ribbon per dive, stacked along Z
/// under a single shared time and depth scale so the profiles are directly
/// comparable. Pure and isolate-friendly; renders through Scene3d.
class CareerGeometryService {
  static const double _zGap = 0.6;

  // Recency ramp: older (faded slate) -> newer (bright cyan).
  static const Color _oldColor = Color(0xFF64748B);
  static const Color _newColor = Color(0xFF22D3EE);
  // Depth ramp: shallow (green) -> deep (indigo).
  static const Color _shallowColor = Color(0xFF34D399);
  static const Color _deepColor = Color(0xFF4F46E5);

  const CareerGeometryService();

  Scene3d build(
    CareerSceneData data, {
    CareerColorMode colorMode = CareerColorMode.recency,
  }) {
    final dives = data.dives;
    if (dives.isEmpty) {
      return const Scene3d(
        layers: [],
        markers: [],
        bounds: SceneBounds(durationSeconds: 1, maxDepthMeters: 1),
      );
    }

    var maxDuration = 1.0;
    var maxDepth = 1.0;
    for (final d in dives) {
      if (d.times.isNotEmpty && d.times.last > maxDuration) {
        maxDuration = d.times.last;
      }
      if (d.maxDepthMeters > maxDepth) maxDepth = d.maxDepthMeters;
    }

    final count = dives.length;
    final halfZ = count <= 1 ? 0.0 : (count - 1) * 0.5 * _zGap;
    final bounds = SceneBounds(
      durationSeconds: maxDuration,
      maxDepthMeters: maxDepth,
      sceneMinZ: -halfZ - SceneBounds.zHalfWidth,
      sceneMaxZ: halfZ + SceneBounds.zHalfWidth,
    );

    final layers = <SceneLayer>[
      for (final dive in dives)
        SceneLayer(
          RibbonBuilder.build(
            times: dive.times,
            depths: dive.depths,
            sampleColors: _uniformColor(
              _colorFor(dive, count, maxDepth, colorMode),
              dive.times.length,
            ),
            bounds: bounds,
            zCenter: count <= 1 ? 0.0 : -halfZ + dive.index * _zGap,
          ),
        ),
    ];

    return Scene3d(layers: layers, markers: const [], bounds: bounds);
  }

  Color _colorFor(
    CareerDiveInput dive,
    int count,
    double maxDepth,
    CareerColorMode mode,
  ) {
    switch (mode) {
      case CareerColorMode.recency:
        final t = count <= 1 ? 1.0 : dive.index / (count - 1);
        return Color.lerp(_oldColor, _newColor, t)!;
      case CareerColorMode.depth:
        final t = maxDepth <= 0 ? 0.0 : (dive.maxDepthMeters / maxDepth);
        return Color.lerp(_shallowColor, _deepColor, t.clamp(0.0, 1.0))!;
    }
  }

  Float32List _uniformColor(Color color, int sampleCount) {
    final out = Float32List(sampleCount * 3);
    for (var i = 0; i < sampleCount; i++) {
      out[i * 3] = color.r;
      out[i * 3 + 1] = color.g;
      out[i * 3 + 2] = color.b;
    }
    return out;
  }
}
