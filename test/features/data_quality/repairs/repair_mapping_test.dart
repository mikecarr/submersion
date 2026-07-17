import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/data_quality/domain/entities/quality_finding.dart';
import 'package:submersion/features/data_quality/domain/repairs/quality_repair_action.dart';

QualityFinding f({
  required String detectorId,
  Map<String, Object?> params = const {},
  String? relatedDiveId,
}) => QualityFinding(
  id: 'f1',
  diveId: 'd1',
  relatedDiveId: relatedDiveId,
  detectorId: detectorId,
  detectorVersion: 1,
  category: QualityCategory.profile,
  severity: QualitySeverity.warning,
  status: QualityStatus.open,
  params: params,
  createdAt: DateTime.utc(2026, 7, 17),
  updatedAt: DateTime.utc(2026, 7, 17),
);

void main() {
  test('clock offset maps to a pre-filled inverse time shift', () {
    final actions = repairOptionsFor(
      f(detectorId: 'clock_offset', params: {'offsetHours': 3}),
    );
    final shift = actions.whereType<TimeShiftRepair>().single;
    expect(shift.suggestedOffset, const Duration(hours: -3));
    expect(shift.offerImportWide, isTrue);
  });

  test('duplicate maps to consolidate with the pair', () {
    final actions = repairOptionsFor(
      f(detectorId: 'duplicate', relatedDiveId: 'd2'),
    );
    final c = actions.whereType<ConsolidateDuplicateRepair>().single;
    expect(c.targetDiveId, 'd1');
    expect(c.secondaryDiveId, 'd2');
  });

  test('split pair maps to combine', () {
    final actions = repairOptionsFor(
      f(detectorId: 'split_pair', relatedDiveId: 'd2'),
    );
    expect(actions.whereType<CombineSplitRepair>().single.diveIds, [
      'd1',
      'd2',
    ]);
  });

  test('maxdepth mismatch maps to recompute, not despike', () {
    final actions = repairOptionsFor(
      f(detectorId: 'depth_spike', params: {'storedMaxDepth': 40.0}),
    );
    expect(actions.whereType<RecomputeMetricsRepair>(), hasLength(1));
    expect(actions.whereType<DespikeRepair>(), isEmpty);
  });

  test('gas_mod gets navigation only (judgment repair)', () {
    final actions = repairOptionsFor(
      f(detectorId: 'gas_mod', params: {'peakPpO2': 2.25}),
    );
    expect(actions, hasLength(1));
    expect(actions.single, isA<GoToDiveRepair>());
  });

  test('every detector id yields at least one action', () {
    for (final id in [
      'clock_offset',
      'duplicate',
      'split_pair',
      'sample_gap',
      'depth_spike',
      'impossible_rate',
      'temp_anomaly',
      'pressure_anomaly',
      'gas_mod',
      'tank_assignment',
      'source_conflict',
    ]) {
      expect(
        repairOptionsFor(f(detectorId: id, relatedDiveId: 'd2')),
        isNotEmpty,
        reason: id,
      );
    }
  });
}
