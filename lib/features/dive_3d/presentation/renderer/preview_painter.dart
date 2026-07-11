import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:submersion/features/dive_3d/domain/entities/mesh_data.dart';
import 'package:submersion/features/dive_3d/domain/geometry/marker_layout.dart';
import 'package:submersion/features/dive_3d/domain/scene_3d.dart';
import 'package:submersion/features/dive_3d/presentation/renderer/scene_projector.dart';
import 'package:submersion/features/dive_3d/presentation/scene_overlay.dart';

/// Paints a Scene3d through SceneProjector with drawVertices. Layers paint
/// back-to-front in list order and triangles within each mesh are
/// depth-sorted, which is sufficient painter's-algorithm ordering for the
/// scene's layered translucency. This is the app's one 3D rasterizer: the
/// preview card paints it with the default camera, the interactive
/// viewport drives the camera parameters from gestures. Layers whose
/// overlay is toggled off (and markers when the markers overlay is off)
/// are skipped.
class Dive3dScenePainter extends CustomPainter {
  final Scene3d scene;
  final double yawDegrees;
  final double pitchDegrees;
  final double zoom;
  final Set<SceneOverlay>? visibleOverlays;

  const Dive3dScenePainter({
    required this.scene,
    this.yawDegrees = -32,
    this.pitchDegrees = 22,
    this.zoom = 1.0,
    this.visibleOverlays,
  });

  bool _visible(SceneOverlay? overlay) =>
      overlay == null ||
      visibleOverlays == null ||
      visibleOverlays!.contains(overlay);

  @override
  void paint(Canvas canvas, Size size) {
    final projector = SceneProjector(
      size: size,
      bounds: scene.bounds,
      yawDegrees: yawDegrees,
      pitchDegrees: pitchDegrees,
      zoom: zoom,
    );
    for (final layer in scene.layers) {
      if (_visible(layer.overlay)) _paintMesh(canvas, projector, layer.mesh);
    }
    if (_visible(SceneOverlay.markers)) _paintMarkers(canvas, projector);
  }

  void _paintMesh(Canvas canvas, SceneProjector projector, MeshData mesh) {
    final n = mesh.vertexCount;
    if (n == 0) return;
    final screen = Float32List(n * 2);
    final colors = Int32List(n);
    final alpha = (mesh.opacity * 255).round() << 24;
    for (var i = 0; i < n; i++) {
      final p = projector.project(
        mesh.positions[i * 3],
        mesh.positions[i * 3 + 1],
        mesh.positions[i * 3 + 2],
      );
      screen[i * 2] = p.dx;
      screen[i * 2 + 1] = p.dy;
      colors[i] =
          alpha |
          ((mesh.colors[i * 3] * 255).round() << 16) |
          ((mesh.colors[i * 3 + 1] * 255).round() << 8) |
          (mesh.colors[i * 3 + 2] * 255).round();
    }

    // Depth-sort triangles back-to-front by mean view depth.
    final triCount = mesh.triangleCount;
    final order = List<int>.generate(triCount, (i) => i);
    final depths = Float32List(triCount);
    for (var t = 0; t < triCount; t++) {
      var d = 0.0;
      for (var k = 0; k < 3; k++) {
        final v = mesh.indices[t * 3 + k];
        d += projector.viewDepth(
          mesh.positions[v * 3],
          mesh.positions[v * 3 + 1],
          mesh.positions[v * 3 + 2],
        );
      }
      depths[t] = d / 3;
    }
    order.sort((a, b) => depths[a].compareTo(depths[b]));

    final sorted = Uint16List(triCount * 3);
    for (var t = 0; t < triCount; t++) {
      final src = order[t] * 3;
      sorted[t * 3] = mesh.indices[src];
      sorted[t * 3 + 1] = mesh.indices[src + 1];
      sorted[t * 3 + 2] = mesh.indices[src + 2];
    }

    canvas.drawVertices(
      Vertices.raw(
        VertexMode.triangles,
        screen,
        colors: colors,
        indices: sorted,
      ),
      BlendMode.dst,
      Paint(),
    );
  }

  void _paintMarkers(Canvas canvas, SceneProjector projector) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final marker in scene.markers) {
      paint.color = switch (marker.kind) {
        SceneMarkerKind.gasSwitch => const Color(0xFF22C55E),
        SceneMarkerKind.bookmark => const Color(0xFFF59E0B),
        SceneMarkerKind.photo => const Color(0xFF00D4FF),
      };
      canvas.drawCircle(projector.project(marker.x, marker.y, 0), 4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant Dive3dScenePainter oldDelegate) =>
      !identical(oldDelegate.scene, scene) ||
      oldDelegate.yawDegrees != yawDegrees ||
      oldDelegate.pitchDegrees != pitchDegrees ||
      oldDelegate.zoom != zoom ||
      oldDelegate.visibleOverlays != visibleOverlays;
}
