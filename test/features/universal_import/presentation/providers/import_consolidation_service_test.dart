import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:submersion/features/dive_import/domain/services/dive_matcher.dart';
import 'package:submersion/features/dive_log/data/services/dive_consolidation_service.dart';
import 'package:submersion/features/dive_log/data/services/dive_merge_snapshot.dart';
import 'package:submersion/features/universal_import/data/services/import_duplicate_checker.dart';
import 'package:submersion/features/universal_import/presentation/providers/import_consolidation_service.dart';

@GenerateMocks([DiveConsolidationService])
import 'import_consolidation_service_test.mocks.dart';

const _emptySnapshot = DiveMergeSnapshot(
  mergedDiveId: 'target-dive',
  diveRows: [],
  profileRows: [],
  tankRows: [],
  weightRows: [],
  customFieldRows: [],
  equipmentRows: [],
  diveTypeRows: [],
  tagRows: [],
  buddyRows: [],
  sightingRows: [],
  eventRows: [],
  gasSwitchRows: [],
  tankPressureRows: [],
  dataSourceRows: [],
  tideRows: [],
  mediaDiveIds: {},
);

void main() {
  late MockDiveConsolidationService mockConsolidationService;

  setUp(() {
    mockConsolidationService = MockDiveConsolidationService();
    when(
      mockConsolidationService.apply(
        targetDiveId: anyNamed('targetDiveId'),
        secondaryDiveIds: anyNamed('secondaryDiveIds'),
      ),
    ).thenAnswer(
      (invocation) async => DiveConsolidationOutcome(
        targetDiveId: invocation.namedArguments[#targetDiveId] as String,
        snapshot: _emptySnapshot,
      ),
    );
  });

  group('performConsolidations', () {
    test('returns 0 for empty indices', () async {
      final count = await performConsolidations(
        indices: <int>{},
        diveIdByIndex: {0: 'new-dive-1'},
        duplicateResult: const ImportDuplicateResult(
          diveMatches: {
            0: DiveMatchResult(
              diveId: 'existing-dive-1',
              score: 0.9,
              timeDifferenceMs: 100,
            ),
          },
        ),
        consolidationService: mockConsolidationService,
      );

      expect(count, 0);
      verifyNever(
        mockConsolidationService.apply(
          targetDiveId: anyNamed('targetDiveId'),
          secondaryDiveIds: anyNamed('secondaryDiveIds'),
        ),
      );
    });

    test('returns 0 when duplicateResult is null', () async {
      final count = await performConsolidations(
        indices: {0},
        diveIdByIndex: {0: 'new-dive-1'},
        duplicateResult: null,
        consolidationService: mockConsolidationService,
      );

      expect(count, 0);
      verifyNever(
        mockConsolidationService.apply(
          targetDiveId: anyNamed('targetDiveId'),
          secondaryDiveIds: anyNamed('secondaryDiveIds'),
        ),
      );
    });

    test('returns 0 when duplicateResult has no match for index', () async {
      final count = await performConsolidations(
        indices: {0},
        diveIdByIndex: {0: 'new-dive-1'},
        duplicateResult: const ImportDuplicateResult(diveMatches: {}),
        consolidationService: mockConsolidationService,
      );

      expect(count, 0);
      verifyNever(
        mockConsolidationService.apply(
          targetDiveId: anyNamed('targetDiveId'),
          secondaryDiveIds: anyNamed('secondaryDiveIds'),
        ),
      );
    });

    test(
      'returns 0 when diveIdByIndex has no persisted dive id for index',
      () async {
        final count = await performConsolidations(
          indices: {0},
          diveIdByIndex: const {},
          duplicateResult: const ImportDuplicateResult(
            diveMatches: {
              0: DiveMatchResult(
                diveId: 'existing-dive-1',
                score: 0.9,
                timeDifferenceMs: 100,
              ),
            },
          ),
          consolidationService: mockConsolidationService,
        );

        expect(count, 0);
        verifyNever(
          mockConsolidationService.apply(
            targetDiveId: anyNamed('targetDiveId'),
            secondaryDiveIds: anyNamed('secondaryDiveIds'),
          ),
        );
      },
    );

    test('folds the freshly-imported dive into the matched dive via '
        'DiveConsolidationService.apply', () async {
      final count = await performConsolidations(
        indices: {0},
        diveIdByIndex: {0: 'new-dive-1'},
        duplicateResult: const ImportDuplicateResult(
          diveMatches: {
            0: DiveMatchResult(
              diveId: 'existing-dive-1',
              score: 0.9,
              timeDifferenceMs: 100,
            ),
          },
        ),
        consolidationService: mockConsolidationService,
      );

      expect(count, 1);
      verify(
        mockConsolidationService.apply(
          targetDiveId: 'existing-dive-1',
          secondaryDiveIds: ['new-dive-1'],
        ),
      ).called(1);
    });

    test('handles multiple indices, each folded into its own match', () async {
      final count = await performConsolidations(
        indices: {0, 1},
        diveIdByIndex: {0: 'new-dive-0', 1: 'new-dive-1'},
        duplicateResult: const ImportDuplicateResult(
          diveMatches: {
            0: DiveMatchResult(
              diveId: 'existing-dive-a',
              score: 0.9,
              timeDifferenceMs: 100,
            ),
            1: DiveMatchResult(
              diveId: 'existing-dive-b',
              score: 0.95,
              timeDifferenceMs: 50,
            ),
          },
        ),
        consolidationService: mockConsolidationService,
      );

      expect(count, 2);
      verify(
        mockConsolidationService.apply(
          targetDiveId: 'existing-dive-a',
          secondaryDiveIds: ['new-dive-0'],
        ),
      ).called(1);
      verify(
        mockConsolidationService.apply(
          targetDiveId: 'existing-dive-b',
          secondaryDiveIds: ['new-dive-1'],
        ),
      ).called(1);
    });

    test('only the matched indices are consolidated; unmatched ones are '
        'silently skipped and do not affect the count', () async {
      final count = await performConsolidations(
        indices: {0, 1},
        diveIdByIndex: {0: 'new-dive-0', 1: 'new-dive-1'},
        duplicateResult: const ImportDuplicateResult(
          diveMatches: {
            0: DiveMatchResult(
              diveId: 'existing-dive-a',
              score: 0.9,
              timeDifferenceMs: 100,
            ),
          },
        ),
        consolidationService: mockConsolidationService,
      );

      expect(count, 1);
      verify(
        mockConsolidationService.apply(
          targetDiveId: 'existing-dive-a',
          secondaryDiveIds: ['new-dive-0'],
        ),
      ).called(1);
      verifyNever(
        mockConsolidationService.apply(
          targetDiveId: 'existing-dive-b',
          secondaryDiveIds: anyNamed('secondaryDiveIds'),
        ),
      );
    });
  });
}
