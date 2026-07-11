import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_3d/domain/entities/mesh_data.dart';
import 'package:submersion/features/dive_3d/presentation/renderer/three_adapter.dart';

void main() {
  test('converts MeshData to a BufferGeometry with matching attributes', () {
    final mesh = MeshData(
      positions: Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
      indices: Uint32List.fromList([0, 1, 2]),
      colors: Float32List.fromList([1, 0, 0, 0, 1, 0, 0, 0, 1]),
      opacity: 0.5,
    );
    final geometry = ThreeAdapter.toBufferGeometry(mesh);
    expect(geometry.getAttributeFromString('position').count, 3);
    expect(geometry.getAttributeFromString('color').count, 3);
  });
}
