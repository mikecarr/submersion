import 'clock_offset_detector.dart';
import 'depth_spike_detector.dart';
import 'duplicate_detector.dart';
import 'gas_mod_detector.dart';
import 'impossible_rate_detector.dart';
import 'pressure_anomaly_detector.dart';
import 'quality_detector.dart';
import 'sample_gap_detector.dart';
import 'source_conflict_detector.dart';
import 'split_pair_detector.dart';
import 'tank_assignment_detector.dart';
import 'temp_anomaly_detector.dart';

const List<QualityDetector> kQualityDetectors = [
  ClockOffsetDetector(),
  DuplicateDetector(),
  SplitPairDetector(),
  SampleGapDetector(),
  DepthSpikeDetector(),
  ImpossibleRateDetector(),
  TempAnomalyDetector(),
  PressureAnomalyDetector(),
  GasModDetector(),
  TankAssignmentDetector(),
  SourceConflictDetector(),
];

Map<String, int> qualityDetectorVersions() => {
  for (final d in kQualityDetectors) d.id: d.version,
};
