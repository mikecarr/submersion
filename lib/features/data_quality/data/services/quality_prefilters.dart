import 'package:drift/drift.dart';

import 'package:submersion/core/database/database.dart';
import 'package:submersion/core/services/database_service.dart';
import 'package:submersion/features/data_quality/domain/quality_thresholds.dart';

/// Cheap SQL passes that narrow the full library to per-detector candidate
/// sets before any context is built. A dive absent from a detector's set is
/// one that detector structurally cannot flag (no profile rows, no second
/// source, ...), so retiring its old findings without re-running is correct.
class QualityPrefilters {
  QualityPrefilters();

  AppDatabase get _db => DatabaseService.instance.database;

  Future<Map<String, Set<String>>> candidatesByDetector({DateTime? now}) async {
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;

    Future<Set<String>> ids(
      String sql, [
      List<Variable> vars = const [],
    ]) async {
      final rows = await _db.customSelect(sql, variables: vars).get();
      return {for (final r in rows) r.read<String>('id')};
    }

    final withProfiles = await ids(
      'SELECT d.id AS id FROM dives d WHERE EXISTS '
      '(SELECT 1 FROM dive_profiles p WHERE p.dive_id = d.id)',
    );
    final withPressures = await ids(
      'SELECT d.id AS id FROM dives d WHERE EXISTS '
      '(SELECT 1 FROM tank_pressure_profiles t WHERE t.dive_id = d.id)',
    );
    final withTanks = await ids(
      'SELECT d.id AS id FROM dives d WHERE EXISTS '
      '(SELECT 1 FROM dive_tanks t WHERE t.dive_id = d.id)',
    );
    final multiSource = await ids(
      'SELECT d.id AS id FROM dives d WHERE '
      '(SELECT COUNT(*) FROM dive_data_sources s WHERE s.dive_id = d.id) >= 2',
    );
    final pairWindow = await ids(
      'SELECT DISTINCT a.id AS id FROM dives a JOIN dives b ON a.id != b.id '
      'AND a.diver_id IS b.diver_id '
      'AND ABS(COALESCE(a.entry_time, a.dive_date_time) - '
      'COALESCE(b.entry_time, b.dive_date_time)) <= ?1',
      [Variable.withInt(QualityThresholds.neighborWindow.inMilliseconds)],
    );
    final timeOutliers = await ids(
      'SELECT d.id AS id FROM dives d WHERE '
      'COALESCE(d.entry_time, d.dive_date_time) > ?1 OR '
      'COALESCE(d.entry_time, d.dive_date_time) < ?2',
      [
        Variable.withInt(
          nowMs +
              const Duration(
                days: QualityThresholds.futureGraceDays,
              ).inMilliseconds,
        ),
        Variable.withInt(
          DateTime.utc(
            QualityThresholds.minPlausibleYear,
          ).millisecondsSinceEpoch,
        ),
      ],
    );
    final scalarTempOutliers = await ids(
      'SELECT d.id AS id FROM dives d WHERE d.water_temp IS NOT NULL AND '
      '(d.water_temp < ?1 OR d.water_temp > ?2)',
      [
        const Variable(QualityThresholds.waterTempMinC),
        const Variable(QualityThresholds.waterTempMaxC),
      ],
    );

    return {
      'clock_offset': {...timeOutliers, ...multiSource, ...pairWindow},
      'duplicate': pairWindow,
      'split_pair': pairWindow,
      'sample_gap': withProfiles,
      'depth_spike': withProfiles,
      'impossible_rate': withProfiles,
      'temp_anomaly': {...withProfiles, ...scalarTempOutliers},
      'pressure_anomaly': {...withPressures, ...withTanks},
      'gas_mod': withTanks.intersection(withProfiles),
      'tank_assignment': withPressures,
      'source_conflict': multiSource,
    };
  }
}
