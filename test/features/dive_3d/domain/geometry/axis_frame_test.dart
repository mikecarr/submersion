import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_3d/domain/geometry/axis_frame.dart';
import 'package:submersion/features/dive_3d/domain/geometry/scene_bounds.dart';

void main() {
  const bounds = SceneBounds(
    durationSeconds: 1,
    maxDepthMeters: 1,
    sceneMinY: 0,
    sceneMaxY: 3.9,
  );

  test('produces exactly one segment per axis', () {
    final frame = AxisFrame.build(bounds, referenceY: 3.0);
    expect(frame.segments.where((s) => s.role == AxisRole.axisX).length, 1);
    expect(frame.segments.where((s) => s.role == AxisRole.axisY).length, 1);
    expect(frame.segments.where((s) => s.role == AxisRole.axisZ).length, 1);
  });

  test('axes originate at the (0, sceneMinY, sceneMinZ) corner', () {
    final frame = AxisFrame.build(bounds, referenceY: 3.0);
    final x = frame.segments.firstWhere((s) => s.role == AxisRole.axisX);
    expect(x.x1, 0);
    expect(x.y1, bounds.sceneMinY);
    expect(x.z1, bounds.sceneMinZ);
    expect(x.x2, SceneBounds.xSpan); // X axis spans the full time extent
  });

  test('has a Y tick at the reference (100%) height', () {
    final frame = AxisFrame.build(bounds, referenceY: 3.0);
    final ticks = frame.segments.where((s) => s.role == AxisRole.tick);
    expect(ticks.any((t) => (t.y1 - 3.0).abs() < 1e-9), isTrue);
    // 0% and 50% ticks too.
    expect(ticks.any((t) => t.y1.abs() < 1e-9), isTrue);
    expect(ticks.any((t) => (t.y1 - 1.5).abs() < 1e-9), isTrue);
  });

  test('emits floor and wall grid segments', () {
    final frame = AxisFrame.build(bounds, referenceY: 3.0);
    expect(
      frame.segments.where((s) => s.role == AxisRole.frameGrid).length,
      greaterThan(4),
    );
  });
}
