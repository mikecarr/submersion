import 'dart:typed_data';
import 'dart:ui';

import 'package:submersion/features/dive_3d/domain/entities/mesh_data.dart';
import 'package:submersion/features/dive_3d/domain/geometry/scene_bounds.dart';
import 'package:submersion/features/dive_3d/domain/scene_3d.dart';
import 'package:submersion/features/dive_3d/domain/tissue/chain_time_axis.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_replay_result.dart';

/// Which inert gas the tissue surface renders.
enum TissueGas { combined, n2, he }

/// What the surface height and color mean.
enum TissueColorMode {
  /// Height/color = supersaturation as a fraction of the M-value limit
  /// (1.0 = at the deco ceiling). The interpretable default.
  mValue,

  /// Height/color = absolute inert-gas loading (bar).
  absolute,
}

/// Builds the "tissue landscape": a height-field grid over
/// (chain-time column) x (16 compartments). In the default %M-value mode the
/// height and color both encode how close each tissue is to its M-value
/// limit, so a red danger plane at 100% shows exactly which tissues
/// approached the deco ceiling and when. Renders through Scene3d unchanged.
class TissueSurfaceBuilder {
  /// Scene-Y height representing 100% of the M-value limit.
  static const double referenceHeight = 2.5;

  /// Surface height is capped here (violations poke just above the plane).
  static const double maxDisplayFraction = 1.3;

  /// Depth-context ribbon depth (scene Y units below the baseline).
  static const double depthContextHeight = 1.4;

  static const Color _dangerPlane = Color(0xFFEF4444);
  static const Color _depthColor = Color(0xFF38BDF8);

  static double _zOf(int compartment, int count) {
    if (count <= 1) return 0;
    final t = compartment / (count - 1);
    return -SceneBounds.zSlabHalfWidth + t * 2 * SceneBounds.zSlabHalfWidth;
  }

  /// Green (well below the limit) -> amber -> red (at/over the M-value).
  static Color _mValueColor(double frac) {
    final f = frac.clamp(0.0, maxDisplayFraction);
    if (f <= 0.7) {
      return Color.lerp(
        const Color(0xFF22C55E),
        const Color(0xFFEAB308),
        f / 0.7,
      )!;
    }
    return Color.lerp(
      const Color(0xFFEAB308),
      const Color(0xFFEF4444),
      ((f - 0.7) / 0.3).clamp(0.0, 1.0),
    )!;
  }

  static Color _loadingColor(double frac) => Color.lerp(
    const Color(0xFF0EA5E9),
    const Color(0xFFA855F7),
    frac.clamp(0.0, 1.0),
  )!;

  static double _loadingBar(
    TissueReplayResult r,
    int col,
    int c,
    TissueGas g,
  ) => switch (g) {
    TissueGas.combined => r.combined(col, c),
    TissueGas.n2 => r.loadingN2(col, c),
    TissueGas.he => r.loadingHe(col, c),
  };

  /// The 0..maxDisplayFraction metric for (col, compartment) under [mode].
  static double _metric(
    TissueReplayResult r,
    int col,
    int c,
    TissueGas gas,
    TissueColorMode mode,
  ) {
    if (mode == TissueColorMode.mValue) return r.gradient(col, c);
    final maxLoad = r.maxLoadingBar <= 0 ? 1.0 : r.maxLoadingBar;
    return _loadingBar(r, col, c, gas) / maxLoad;
  }

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
    final positions = Float32List(cols * k * 3);
    final colors = Float32List(cols * k * 3);
    for (var col = 0; col < cols; col++) {
      final x = axis.xOf(result.times[col]);
      for (var c = 0; c < k; c++) {
        final vi = (col * k + c) * 3;
        final frac = _metric(result, col, c, gas, colorMode);
        positions[vi] = x;
        positions[vi + 1] =
            frac.clamp(0.0, maxDisplayFraction) * referenceHeight;
        positions[vi + 2] = _zOf(c, k);
        final color = colorMode == TissueColorMode.mValue
            ? _mValueColor(frac)
            : _loadingColor(frac);
        colors[vi] = color.r;
        colors[vi + 1] = color.g;
        colors[vi + 2] = color.b;
      }
    }
    return MeshData(
      positions: positions,
      indices: _gridIndices(cols, k),
      colors: colors,
      opacity: opacity,
    );
  }

  /// The translucent red plane at 100% of the M-value limit (only
  /// meaningful in %M mode). Tissues rising above it are at/over the ceiling.
  static MeshData dangerPlane({required ChainTimeAxis axis}) {
    const z = SceneBounds.zSlabHalfWidth;
    final positions = Float32List.fromList([
      0,
      referenceHeight,
      -z,
      SceneBounds.xSpan,
      referenceHeight,
      -z,
      0,
      referenceHeight,
      z,
      SceneBounds.xSpan,
      referenceHeight,
      z,
    ]);
    final colors = Float32List(4 * 3);
    for (var i = 0; i < 4; i++) {
      colors[i * 3] = _dangerPlane.r;
      colors[i * 3 + 1] = _dangerPlane.g;
      colors[i * 3 + 2] = _dangerPlane.b;
    }
    return MeshData(
      positions: positions,
      indices: Uint32List.fromList([0, 1, 2, 1, 3, 2]),
      colors: colors,
      opacity: 0.16,
    );
  }

  /// The dive's depth profile as a faint ribbon at the front edge, so the
  /// tissue surface can be read against "where in the dive am I". Y goes
  /// below the baseline (down = deeper).
  static MeshData depthContext({
    required TissueReplayResult result,
    required ChainTimeAxis axis,
  }) {
    final cols = result.columnCount;
    if (cols < 2) {
      return MeshData(
        positions: Float32List(0),
        indices: Uint32List(0),
        colors: Float32List(0),
      );
    }
    var maxDepth = 1.0;
    for (final d in result.depths) {
      if (d > maxDepth) maxDepth = d;
    }
    const zFront = -SceneBounds.zSlabHalfWidth * 1.12;
    const thickness = SceneBounds.zSlabHalfWidth * 0.08;
    final positions = Float32List(cols * 6);
    final colors = Float32List(cols * 6);
    for (var col = 0; col < cols; col++) {
      final x = axis.xOf(result.times[col]);
      final y = -(result.depths[col] / maxDepth) * depthContextHeight;
      final p = col * 6;
      positions[p] = x;
      positions[p + 1] = y;
      positions[p + 2] = zFront - thickness;
      positions[p + 3] = x;
      positions[p + 4] = y;
      positions[p + 5] = zFront + thickness;
      for (var s = 0; s < 2; s++) {
        colors[p + s * 3] = _depthColor.r;
        colors[p + s * 3 + 1] = _depthColor.g;
        colors[p + s * 3 + 2] = _depthColor.b;
      }
    }
    return MeshData(
      positions: positions,
      indices: _stripIndices(cols),
      colors: colors,
      opacity: 0.7,
    );
  }

  /// Cursor path: rides the controlling compartment's surface point per
  /// column in the active [colorMode].
  static ScrubPath scrubPath({
    required TissueReplayResult result,
    required ChainTimeAxis axis,
    required TissueGas gas,
    required TissueColorMode colorMode,
  }) {
    final total = result.totalClockSeconds <= 0
        ? 1.0
        : result.totalClockSeconds;
    return ScrubPath(
      normalizedTimes: [for (final t in result.times) t / total],
      xs: [for (final t in result.times) axis.xOf(t)],
      ys: [
        for (var col = 0; col < result.columnCount; col++)
          _metric(
                result,
                col,
                result.controlling[col],
                gas,
                colorMode,
              ).clamp(0.0, maxDisplayFraction) *
              referenceHeight,
      ],
    );
  }

  static Uint32List _gridIndices(int cols, int k) {
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
    return indices;
  }

  static Uint32List _stripIndices(int pairCount) {
    if (pairCount < 2) return Uint32List(0);
    final indices = Uint32List((pairCount - 1) * 6);
    var j = 0;
    for (var i = 0; i < pairCount - 1; i++) {
      final a = i * 2, b = i * 2 + 1, c = i * 2 + 2, d = i * 2 + 3;
      indices[j++] = a;
      indices[j++] = b;
      indices[j++] = c;
      indices[j++] = b;
      indices[j++] = d;
      indices[j++] = c;
    }
    return indices;
  }
}
