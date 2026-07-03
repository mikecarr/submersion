import 'package:submersion/features/dive_log/data/services/dive_consolidation_service.dart';
import 'package:submersion/features/universal_import/data/services/import_duplicate_checker.dart';

/// Folds consolidate-flagged imported dives into their matched existing
/// dives.
///
/// The dives at [indices] have already been persisted as full standalone
/// dives (via `UddfEntityImporter.import`, in the same call as the rest of
/// the payload's dive selection, so cross-references to trips/sites/buddies
/// from this import resolve correctly) -- [diveIdByIndex] maps each source
/// index to the id that import produced. This function folds each of those
/// freshly-imported dives into the dive matched by [duplicateResult] via
/// [DiveConsolidationService.apply], which carries over every sample
/// column, tank, pressure, and event with attribution, then tombstones the
/// now-redundant standalone dive.
///
/// Returns the number of successful consolidations.
Future<int> performConsolidations({
  required Set<int> indices,
  required Map<int, String> diveIdByIndex,
  required ImportDuplicateResult? duplicateResult,
  required DiveConsolidationService consolidationService,
}) async {
  var count = 0;

  for (final index in indices) {
    final matchResult = duplicateResult?.diveMatchFor(index);
    if (matchResult == null) continue;

    final newDiveId = diveIdByIndex[index];
    if (newDiveId == null) continue;

    await consolidationService.apply(
      targetDiveId: matchResult.diveId,
      secondaryDiveIds: [newDiveId],
    );
    count++;
  }

  return count;
}
