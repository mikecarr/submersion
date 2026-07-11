import 'package:three_js_core/three_js_core.dart' as three;
import 'package:three_js_math/three_js_math.dart' as tmath;

import 'package:submersion/features/dive_3d/domain/entities/mesh_data.dart';

/// The engine boundary: converts engine-agnostic MeshData into three_js
/// objects. Nothing else in dive_3d may import three_js packages (except
/// scene_viewport.dart, which hosts the engine widget). If flutter_scene
/// reaches stable, this file and scene_viewport.dart are the rewrite.
class ThreeAdapter {
  static three.BufferGeometry toBufferGeometry(MeshData mesh) {
    final geometry = three.BufferGeometry();
    geometry.setAttributeFromString(
      'position',
      tmath.Float32BufferAttribute(mesh.positions, 3),
    );
    geometry.setAttributeFromString(
      'color',
      tmath.Float32BufferAttribute(mesh.colors, 3),
    );
    geometry.setIndex(mesh.indices.toList());
    return geometry;
  }

  static three.Mesh toMesh(MeshData mesh) {
    final material = three.MeshBasicMaterial.fromMap({
      'vertexColors': true,
      'side': tmath.DoubleSide,
      'transparent': mesh.opacity < 1.0,
      'opacity': mesh.opacity,
    });
    return three.Mesh(toBufferGeometry(mesh), material);
  }
}
