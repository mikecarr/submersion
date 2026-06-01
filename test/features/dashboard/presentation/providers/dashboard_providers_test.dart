import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_providers.dart';

import '../../../../helpers/mock_providers.dart';

Dive _diveWithEntryTime(DateTime entryTime) => Dive(
  id: 'test-${entryTime.millisecondsSinceEpoch}',
  dateTime: entryTime,
  entryTime: entryTime,
  tanks: const [],
  profile: const [],
  equipment: const [],
  notes: '',
  photoIds: const [],
  sightings: const [],
  weights: const [],
  tags: const [],
);

void main() {
  group('daysSinceLastDiveProvider', () {
    test('returns 0 for a dive that occurred earlier today', () async {
      final now = DateTime.now();
      final todayDive = _diveWithEntryTime(
        DateTime(now.year, now.month, now.day, 8, 0),
      );
      final container = ProviderContainer(
        overrides: [
          recentDivesProvider.overrideWith((ref) async => [todayDive]),
        ],
      );
      addTearDown(container.dispose);

      final days = await container.read(daysSinceLastDiveProvider.future);
      expect(days, 0);
    });

    test(
      'returns 1 for a dive at 11:55 pm yesterday (issue #263 regression)',
      () async {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        final lateDive = _diveWithEntryTime(
          DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 55),
        );
        final container = ProviderContainer(
          overrides: [
            recentDivesProvider.overrideWith((ref) async => [lateDive]),
          ],
        );
        addTearDown(container.dispose);

        final days = await container.read(daysSinceLastDiveProvider.future);
        expect(days, 1);
      },
    );

    test('returns 2 for a dive two calendar days ago', () async {
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      final oldDive = _diveWithEntryTime(
        DateTime(twoDaysAgo.year, twoDaysAgo.month, twoDaysAgo.day, 12, 0),
      );
      final container = ProviderContainer(
        overrides: [
          recentDivesProvider.overrideWith((ref) async => [oldDive]),
        ],
      );
      addTearDown(container.dispose);

      final days = await container.read(daysSinceLastDiveProvider.future);
      expect(days, 2);
    });

    test('returns null when there are no dives', () async {
      final container = ProviderContainer(
        overrides: [recentDivesProvider.overrideWith((ref) async => [])],
      );
      addTearDown(container.dispose);

      final days = await container.read(daysSinceLastDiveProvider.future);
      expect(days, isNull);
    });
  });

  group('personalRecordsProvider', () {
    test('finds longest dive by effectiveRuntime', () async {
      final dives = [
        createTestDiveWithBottomTime(
          id: 'short',
          bottomTime: const Duration(minutes: 20),
          runtime: const Duration(minutes: 25),
          maxDepth: 15.0,
          waterTemp: 24.0,
        ),
        createTestDiveWithBottomTime(
          id: 'long',
          bottomTime: const Duration(minutes: 60),
          runtime: const Duration(minutes: 75),
          maxDepth: 25.0,
          waterTemp: 22.0,
        ),
        createTestDiveWithBottomTime(
          id: 'medium',
          bottomTime: const Duration(minutes: 40),
          runtime: const Duration(minutes: 50),
          maxDepth: 30.0,
          waterTemp: 20.0,
        ),
      ];

      final container = ProviderContainer(
        overrides: [divesProvider.overrideWith((ref) async => dives)],
      );
      addTearDown(container.dispose);

      final records = await container.read(personalRecordsProvider.future);

      expect(records.longestDive, isNotNull);
      expect(records.longestDive!.id, 'long');
      expect(records.longestDive!.effectiveRuntime!.inMinutes, 75);
    });

    test('falls back to bottomTime when runtime is null', () async {
      final dives = [
        createTestDiveWithBottomTime(
          id: 'no-runtime',
          bottomTime: const Duration(minutes: 30),
          runtime: null,
          maxDepth: 20.0,
        ),
        createTestDiveWithBottomTime(
          id: 'shorter',
          bottomTime: const Duration(minutes: 15),
          runtime: null,
          maxDepth: 15.0,
        ),
      ];

      final container = ProviderContainer(
        overrides: [divesProvider.overrideWith((ref) async => dives)],
      );
      addTearDown(container.dispose);

      final records = await container.read(personalRecordsProvider.future);

      expect(records.longestDive, isNotNull);
      expect(records.longestDive!.id, 'no-runtime');
    });

    test('prefers runtime over bottomTime for longest dive', () async {
      // Both dives have the same bottomTime, but different runtimes.
      // The dive with the longer runtime should win.
      final dives = [
        createTestDiveWithBottomTime(
          id: 'short-runtime',
          bottomTime: const Duration(minutes: 40),
          runtime: const Duration(minutes: 45),
          maxDepth: 20.0,
        ),
        createTestDiveWithBottomTime(
          id: 'long-runtime',
          bottomTime: const Duration(minutes: 40),
          runtime: const Duration(minutes: 70),
          maxDepth: 15.0,
        ),
      ];

      final container = ProviderContainer(
        overrides: [divesProvider.overrideWith((ref) async => dives)],
      );
      addTearDown(container.dispose);

      final records = await container.read(personalRecordsProvider.future);

      expect(records.longestDive, isNotNull);
      expect(records.longestDive!.id, 'long-runtime');
    });
  });
}
