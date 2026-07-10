import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_log/data/repositories/dive_repository_impl.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart'
    as domain;
import 'package:submersion/features/dive_sites/data/repositories/site_repository_impl.dart';
import 'package:submersion/features/dive_sites/domain/entities/dive_site.dart';

import '../../../../helpers/test_database.dart';

void main() {
  late DiveRepository repository;

  setUp(() async {
    await setUpTestDatabase();
    repository = DiveRepository();
  });
  tearDown(() async => tearDownTestDatabase());

  group('countDivesSince', () {
    test('counts dives strictly after the boundary', () async {
      await repository.createDive(
        domain.Dive(id: 'before', dateTime: DateTime(2026, 5, 31, 23)),
      );
      await repository.createDive(
        domain.Dive(id: 'boundary', dateTime: DateTime(2026, 6, 1)),
      );
      await repository.createDive(
        domain.Dive(id: 'after', dateTime: DateTime(2026, 6, 15)),
      );

      // Strict >, matching the old Dart filter's isAfter().
      expect(await repository.countDivesSince(DateTime(2026, 6, 1)), 1);
      expect(await repository.countDivesSince(DateTime(2026, 5, 1)), 3);
      expect(await repository.countDivesSince(DateTime(2026, 7, 1)), 0);
    });

    test('scopes by diver id', () async {
      await repository.createDive(
        domain.Dive(id: 'd1', dateTime: DateTime(2026, 6, 2)),
      );
      expect(
        await repository.countDivesSince(
          DateTime(2026, 6, 1),
          diverId: 'nobody',
        ),
        0,
      );
    });
  });

  group('getPersonalRecordIds', () {
    test('selects deepest, coldest, and warmest winners', () async {
      await repository.createDive(
        domain.Dive(
          id: 'shallow-warm',
          dateTime: DateTime(2026, 1, 1),
          maxDepth: 12,
          waterTemp: 29,
        ),
      );
      await repository.createDive(
        domain.Dive(
          id: 'deep-cold',
          dateTime: DateTime(2026, 1, 2),
          maxDepth: 42,
          waterTemp: 8,
        ),
      );

      final winners = await repository.getPersonalRecordIds();
      expect(winners.deepestId, 'deep-cold');
      expect(winners.coldestId, 'deep-cold');
      expect(winners.warmestId, 'shallow-warm');
    });

    test('longest uses the full effectiveRuntime order, including the '
        'profile-span fallback', () async {
      // Explicit runtime: 50 minutes.
      await repository.createDive(
        domain.Dive(
          id: 'explicit',
          dateTime: DateTime(2026, 2, 1),
          runtime: const Duration(minutes: 50),
        ),
      );
      // No runtime/exit/bottom, but a 70-minute profile span: must win.
      await repository.createDive(
        domain.Dive(
          id: 'span-winner',
          dateTime: DateTime(2026, 2, 2),
          profile: [
            for (var t = 0; t <= 4200; t += 60)
              domain.DiveProfilePoint(timestamp: t, depth: 18),
          ],
        ),
      );

      final winners = await repository.getPersonalRecordIds();
      expect(winners.longestId, 'span-winner');
    });

    test('most visited site wins by dive count', () async {
      final siteRepo = SiteRepository();
      final often = await siteRepo.createSite(
        const DiveSite(id: '', name: 'House Reef'),
      );
      final rare = await siteRepo.createSite(
        const DiveSite(id: '', name: 'Far Wall'),
      );

      for (var i = 0; i < 3; i++) {
        await repository.createDive(
          domain.Dive(
            id: 'often-$i',
            dateTime: DateTime(2026, 3, 1 + i),
            site: often,
          ),
        );
      }
      await repository.createDive(
        domain.Dive(id: 'rare-0', dateTime: DateTime(2026, 3, 10), site: rare),
      );

      final winners = await repository.getPersonalRecordIds();
      expect(winners.mostVisitedSiteId, often.id);
      expect(winners.mostVisitedSiteName, 'House Reef');
      expect(winners.mostVisitedSiteCount, 3);
    });

    test('empty database produces no winners', () async {
      final winners = await repository.getPersonalRecordIds();
      expect(winners.deepestId, isNull);
      expect(winners.longestId, isNull);
      expect(winners.coldestId, isNull);
      expect(winners.warmestId, isNull);
      expect(winners.mostVisitedSiteId, isNull);
    });
  });
}
