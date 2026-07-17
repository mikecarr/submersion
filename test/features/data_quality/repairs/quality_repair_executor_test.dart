import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/data_quality/data/repositories/quality_findings_repository.dart';
import 'package:submersion/features/data_quality/data/services/quality_repair_executor.dart';
import 'package:submersion/features/data_quality/data/services/quality_scan_service.dart';
import 'package:submersion/features/data_quality/domain/entities/quality_finding.dart';
import 'package:submersion/features/dive_log/data/repositories/dive_repository_impl.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart'
    as domain;

import '../../../helpers/test_database.dart';

void main() {
  late DiveRepository diveRepo;
  late QualityFindingsRepository findingsRepo;
  late QualityRepairExecutor executor;

  setUp(() async {
    await setUpTestDatabase();
    // The executor queues a targeted rescan; keep it out of the test zone.
    QualityScanScheduler.enabled = false;
    diveRepo = DiveRepository();
    findingsRepo = QualityFindingsRepository();
    executor = QualityRepairExecutor();
  });
  tearDown(() {
    QualityScanScheduler.enabled = true;
    return tearDownTestDatabase();
  });

  Future<QualityFinding> seedFindingForDive(String diveId) async {
    final finding = QualityFinding(
      id: qualityFindingId(diveId: diveId, detectorId: 'clock_offset'),
      diveId: diveId,
      detectorId: 'clock_offset',
      detectorVersion: 1,
      category: QualityCategory.time,
      severity: QualitySeverity.warning,
      status: QualityStatus.open,
      createdAt: DateTime.utc(2026, 7, 17),
      updatedAt: DateTime.utc(2026, 7, 17),
    );
    await findingsRepo.applyScanResults(
      scopeDiveIds: {diveId},
      ranDetectorIds: {'clock_offset'},
      produced: [finding],
    );
    return finding;
  }

  test('shiftTimes shifts, resolves the finding, and undo restores', () async {
    final entry = DateTime.utc(2026, 7, 1, 10);
    await diveRepo.createDive(
      domain.Dive(id: 'd1', dateTime: entry, entryTime: entry),
    );
    final finding = await seedFindingForDive('d1');

    final undo = await executor.shiftTimes(
      diveIds: ['d1'],
      offset: const Duration(hours: -6),
      findingId: finding.id,
    );

    expect(
      (await diveRepo.getDiveById('d1'))!.entryTime,
      entry.subtract(const Duration(hours: 6)),
    );
    final resolved = await findingsRepo.getFindings(diveId: 'd1');
    expect(resolved.single.status, QualityStatus.resolved);

    await undo!();
    expect((await diveRepo.getDiveById('d1'))!.entryTime, entry);
  });

  test(
    'divesInSameImport falls back to just the dive without importId',
    () async {
      await diveRepo.createDive(
        domain.Dive(id: 'd1', dateTime: DateTime.utc(2026, 7, 1)),
      );
      expect(await executor.divesInSameImport('d1'), ['d1']);
    },
  );
}
