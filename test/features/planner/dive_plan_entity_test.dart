import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/deco/schedule_policy.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/planner/domain/entities/dive_plan.dart';
import 'package:submersion/features/dive_planner/domain/entities/plan_segment.dart';

DivePlan _plan({
  double sacBottom = 15.0,
  double? sacDeco,
  double? sacStressed,
  List<PlanSegment> segments = const [],
}) {
  return DivePlan(
    id: 'p1',
    name: 'Test plan',
    gfLow: 50,
    gfHigh: 80,
    sacBottom: sacBottom,
    sacDeco: sacDeco,
    sacStressed: sacStressed,
    segments: segments,
    createdAt: DateTime(2026, 7, 5),
    updatedAt: DateTime(2026, 7, 5),
  );
}

void main() {
  group('DivePlan', () {
    test('SAC defaults derive from bottom SAC', () {
      final plan = _plan(sacBottom: 15.0);
      expect(plan.sacDecoEffective, closeTo(12.0, 1e-9));
      expect(plan.sacStressedEffective, closeTo(37.5, 1e-9));
    });

    test('explicit SAC values override the derived defaults', () {
      final plan = _plan(sacBottom: 15.0, sacDeco: 14.0, sacStressed: 40.0);
      expect(plan.sacDecoEffective, 14.0);
      expect(plan.sacStressedEffective, 40.0);
    });

    test('maxDepth spans segment start and end depths', () {
      const gas = GasMix(o2: 21);
      final plan = _plan(
        segments: [
          PlanSegment.descent(
            id: 's1',
            targetDepth: 42.0,
            tankId: 't1',
            gasMix: gas,
          ),
          PlanSegment.bottom(
            id: 's2',
            depth: 42.0,
            durationMinutes: 20,
            tankId: 't1',
            gasMix: gas,
          ),
        ],
      );
      expect(plan.maxDepth, 42.0);
      expect(_plan().maxDepth, 0.0);
    });

    test('copyWith clear-flags null out nullable fields', () {
      final plan = _plan().copyWith(
        airBreaks: const AirBreakPolicy(),
        surfaceInterval: const Duration(hours: 1),
        sourceDiveId: 'dive-1',
      );
      expect(plan.airBreaks, isNotNull);
      final cleared = plan.copyWith(
        clearAirBreaks: true,
        clearSurfaceInterval: true,
        clearSourceDiveId: true,
      );
      expect(cleared.airBreaks, isNull);
      expect(cleared.surfaceInterval, isNull);
      expect(cleared.sourceDiveId, isNull);
      // Untouched fields survive.
      expect(cleared.name, 'Test plan');
      expect(cleared.gfHigh, 80);
    });
  });
}
