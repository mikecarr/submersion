import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:three_js_angle_renderer/three_js_angle_renderer.dart';
import 'package:three_js_core/three_js_core.dart' as three;
import 'package:three_js_math/three_js_math.dart' as tmath;

// Platform spike for the dive 3D view (plan Task 1). Standalone entrypoint:
//   flutter run -d macos -t lib/dev/three_spike_main.dart
// Proves the exact rendering mode the dive ribbon needs: an indexed
// vertex-colored BufferGeometry triangle strip, plus hand-rolled orbit
// controls (three_js_controls is excluded by dependency constraints).
void main() {
  runApp(const MaterialApp(home: SpikePage()));
}

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  late final ThreeJS threeJs;

  // Orbit state: spherical coordinates around the target.
  double _yaw = 0.6;
  double _pitch = 0.4;
  double _radius = 5.0;
  final tmath.Vector3 _target = tmath.Vector3(1, 0.5, 0.5);

  @override
  void initState() {
    super.initState();
    threeJs = ThreeJS(onSetupComplete: () => setState(() {}), setup: setup);
  }

  Future<void> setup() async {
    threeJs.scene = three.Scene();
    threeJs.camera = three.PerspectiveCamera(
      60,
      threeJs.width / threeJs.height,
      0.1,
      100,
    );
    _applyCamera();

    final geometry = three.BufferGeometry();
    geometry.setAttributeFromString(
      'position',
      tmath.Float32BufferAttribute.fromList([
        0,
        0,
        0,
        0,
        0,
        1,
        1,
        1,
        0,
        1,
        1,
        1,
        2,
        0.5,
        0,
        2,
        0.5,
        1,
      ], 3),
    );
    geometry.setAttributeFromString(
      'color',
      tmath.Float32BufferAttribute.fromList([
        1,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        1,
      ], 3),
    );
    geometry.setIndex([0, 1, 2, 1, 3, 2, 2, 3, 4, 3, 5, 4]);
    final material = three.MeshBasicMaterial.fromMap({
      'vertexColors': true,
      'side': tmath.DoubleSide,
    });
    final mesh = three.Mesh(geometry, material);
    threeJs.scene.add(mesh);
    threeJs.addAnimationEvent((dt) {
      mesh.rotation.y += dt * 0.5;
    });
  }

  void _applyCamera() {
    final cp = math.cos(_pitch), sp = math.sin(_pitch);
    final cy = math.cos(_yaw), sy = math.sin(_yaw);
    threeJs.camera.position.setValues(
      _target.x + _radius * cp * sy,
      _target.y + _radius * sp,
      _target.z + _radius * cp * cy,
    );
    threeJs.camera.lookAt(_target);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _yaw -= details.delta.dx * 0.01;
    _pitch = (_pitch + details.delta.dy * 0.01).clamp(-1.4, 1.4);
    _applyCamera();
  }

  void _onScaleUpdate(double factor) {
    _radius = (_radius / factor).clamp(1.5, 30.0);
    _applyCamera();
  }

  @override
  void dispose() {
    threeJs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('three_js spike')),
      body: Listener(
        onPointerSignal: (signal) {
          if (signal is PointerScrollEvent) {
            _onScaleUpdate(signal.scrollDelta.dy < 0 ? 1.1 : 0.9);
          }
        },
        child: GestureDetector(
          onPanUpdate: _onPanUpdate,
          onDoubleTap: () {
            _yaw = 0.6;
            _pitch = 0.4;
            _radius = 5.0;
            _applyCamera();
          },
          child: threeJs.build(),
        ),
      ),
    );
  }
}
