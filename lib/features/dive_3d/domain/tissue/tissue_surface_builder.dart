import 'dart:typed_data';
import 'dart:ui';

import 'package:submersion/features/dive_3d/domain/entities/mesh_data.dart';
import 'package:submersion/features/dive_3d/domain/geometry/scene_bounds.dart';
import 'package:submersion/features/dive_3d/domain/scene_3d.dart';
import 'package:submersion/features/dive_3d/domain/tissue/chain_time_axis.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_replay_result.dart';

/// Which inert gas the tissue surface renders.
enum TissueGas { combined, n2, he }

/// How the surface is colored.
enum TissueColorMode { mValue, absolute }

/// Builds the "tissue landscape": a height-field grid surface over
/// (chain-time column) x (16 compartments). Height (Y) is inert-gas
/// loading; color is either supersaturation %M (green->amber->red) or
/// absolute loading. Renders through the shared Scene3d/CustomPainter
/// pipeline unchanged.
class TissueSurfaceBuilder {
  /// Peak visual height of the surface, in scene Y units.
  static const double tissueHeight = 3.0;

  // Green -> amber -> red supersaturation ramp.
  static const List<Color> _ramp = [
    Color(0xFF22C55E),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
  ];

  static double _zOf(int compartment, int count) {
    if (count <= 1) return 0;
    final t = compartment / (count - 1);
    return -SceneBounds.zSlabHalfWidth + t * 2 * SceneBounds.zSlabHalfWidth;
  }

  static Color _rampColor(double t) {
    final c = t.clamp(0.0, 1.0) * (_ramp.length - 1);
    final i = c.floor().clamp(0, _ramp.length - 2);
    return Color.lerp(_ramp[i], _ramp[i + 1], c - i)!;
  }

  /// Loading (bar) chosen for the [gas] at (column, compartment).
  static double _loading(TissueReplayResult r, int col, int c, TissueGas gas) =>
      switch (gas) {
        TissueGas.combined => r.combined(col, c),
        TissueGas.n2 => r.loadingN2(col, c),
        TissueGas.he => r.loadingHe(col, c),
      };

  static MeshData buildSurface({
    required TissueReplayResult result,
    required ChainTimeAxis axis,
    required TissueGas gas,
    required TissueColorMode colorMode,
    double opacity = 1.0,
  }) {
    const k = TissueReplayResult.compartmentCount;
    final cols = result.columnCount;
    if (cols < 2) {
      return MeshData(
        positions: Float32List(0),
        indices: Uint32List(0),
        colors: Float32List(0),
      );
    }
    final maxLoad = result.maxLoadingBar <= 0 ? 1.0 : result.maxLoadingBar;
    final positions = Float32List(cols * k * 3);
    final colors = Float32List(cols * k * 3);
    for (var col = 0; col < cols; col++) {
      final x = axis.xOf(result.times[col]);
      for (var c = 0; c < k; c++) {
        final vi = (col * k + c) * 3;
        final load = _loading(result, col, c, gas);
        positions[vi] = x;
        positions[vi + 1] = (load / maxLoad) * tissueHeight;
        positions[vi + 2] = _zOf(c, k);
        final t = colorMode == TissueColorMode.mValue
            ? result.gradient(col, c)
            : load / maxLoad;
        final color = _rampColor(t);
        colors[vi] = color.r;
        colors[vi + 1] = color.g;
        colors[vi + 2] = color.b;
      }
    }
    final indices = Uint32List((cols - 1) * (k - 1) * 6);
    var q = 0;
    for (var col = 0; col < cols - 1; col++) {
      for (var c = 0; c < k - 1; c++) {
        final a = col * k + c;
        final b = col * k + c + 1;
        final cc = (col + 1) * k + c;
        final dd = (col + 1) * k + c + 1;
        indices[q++] = a;
        indices[q++] = b;
        indices[q++] = cc;
        indices[q++] = b;
        indices[q++] = dd;
        indices[q++] = cc;
      }
    }
    return MeshData(
      positions: positions,
      indices: indices,
      colors: colors,
      opacity: opacity,
    );
  }

  /// A bright thin ribbon following the controlling compartment per column.
  static MeshData? buildControllingRidge({
    required TissueReplayResult result,
    required ChainTimeAxis axis,
  }) {
    const k = TissueReplayResult.compartmentCount;
    final cols = result.columnCount;
    if (cols < 2) return null;
    final maxLoad = result.maxLoadingBar <= 0 ? 1.0 : result.maxLoadingBar;
    const halfZ = SceneBounds.zSlabHalfWidth / 12;
    const ridge = Color(0xFFFFFFFF);
    final positions = Float32List(cols * 2 * 3);
    final colors = Float32List(cols * 2 * 3);
    for (var col = 0; col < cols; col++) {
      final c = result.controlling[col];
      final x = axis.xOf(result.times[col]);
      final y = (result.combined(col, c) / maxLoad) * tissueHeight + 0.02;
      final z = _zOf(c, k);
      for (var s = 0; s < 2; s++) {
        final vi = (col * 2 + s) * 3;
        positions[vi] = x;
        positions[vi + 1] = y;
        positions[vi + 2] = z + (s == 0 ? -halfZ : halfZ);
        colors[vi] = ridge.r;
        colors[vi + 1] = ridge.g;
        colors[vi + 2] = ridge.b;
      }
    }
    final indices = Uint32List((cols - 1) * 6);
    var q = 0;
    for (var col = 0; col < cols - 1; col++) {
      final a = col * 2, b = col * 2 + 1, cc = col * 2 + 2, dd = col * 2 + 3;
      indices[q++] = a;
      indices[q++] = b;
      indices[q++] = cc;
      indices[q++] = b;
      indices[q++] = dd;
      indices[q++] = cc;
    }
    return MeshData(positions: positions, indices: indices, colors: colors);
  }

  /// Cursor path: rides the top of the controlling ridge per column.
  static ScrubPath scrubPath({
    required TissueReplayResult result,
    required ChainTimeAxis axis,
  }) {
    final maxLoad = result.maxLoadingBar <= 0 ? 1.0 : result.maxLoadingBar;
    final total = result.totalClockSeconds <= 0
        ? 1.0
        : result.totalClockSeconds;
    return ScrubPath(
      normalizedTimes: [for (final t in result.times) t / total],
      xs: [for (final t in result.times) axis.xOf(t)],
      ys: [
        for (var col = 0; col < result.columnCount; col++)
          (result.combined(col, result.controlling[col]) / maxLoad) *
              tissueHeight,
      ],
    );
  }
}
