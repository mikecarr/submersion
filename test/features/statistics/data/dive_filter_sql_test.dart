import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart'
    as dive_entity;
import 'package:submersion/features/dive_log/domain/models/dive_filter_state.dart';
import 'package:submersion/features/statistics/data/dive_filter_sql.dart';

import '../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = await setUpTestDatabase();
  });
  tearDown(() async {
    await tearDownTestDatabase();
  });

  final now = DateTime(2026, 6, 1).millisecondsSinceEpoch;

  Future<void> insertDive(
    String id, {
    DateTime? date,
    String? siteId,
    double? maxDepth,
    int? rating,
    int? bottomTimeSeconds,
    bool favorite = false,
  }) async {
    await db
        .into(db.dives)
        .insert(
          DivesCompanion(
            id: Value(id),
            diveDateTime: Value(
              (date ?? DateTime(2026, 6, 1)).millisecondsSinceEpoch,
            ),
            siteId: Value(siteId),
            maxDepth: Value(maxDepth),
            rating: Value(rating),
            bottomTime: Value(bottomTimeSeconds),
            isFavorite: Value(favorite),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  Future<void> insertSite(String id) async {
    await db
        .into(db.diveSites)
        .insert(
          DiveSitesCompanion(
            id: Value(id),
            name: Value('Site $id'),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  Future<void> insertTag(String id) async {
    await db
        .into(db.tags)
        .insert(
          TagsCompanion(
            id: Value(id),
            name: Value('Tag $id'),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  Future<void> linkTag(String diveId, String tagId) async {
    await db
        .into(db.diveTags)
        .insert(
          DiveTagsCompanion(
            id: Value('$diveId-$tagId'),
            diveId: Value(diveId),
            tagId: Value(tagId),
            createdAt: Value(now),
          ),
        );
  }

  Future<Set<String>> idsMatching(DiveFilterState filter) async {
    final f = buildFilteredDiveIdSubquery(filter);
    final sql = f.subquery.isEmpty ? 'SELECT id FROM dives' : f.subquery;
    final rows = await db
        .customSelect(sql, variables: f.params.map((p) => Variable(p)).toList())
        .get();
    return rows.map((r) => r.read<String>('id')).toSet();
  }

  test('empty filter is a no-op (returns all dives)', () async {
    await insertDive('a');
    await insertDive('b');
    final f = buildFilteredDiveIdSubquery(const DiveFilterState());
    expect(f.subquery, '');
    expect(f.params, isEmpty);
    expect(await idsMatching(const DiveFilterState()), {'a', 'b'});
  });

  test('date range filters inclusively through the end day', () async {
    await insertDive('before', date: DateTime(2026, 1, 1));
    await insertDive('inside', date: DateTime(2026, 6, 15));
    await insertDive('endday', date: DateTime(2026, 6, 30, 23, 0));
    await insertDive('after', date: DateTime(2026, 8, 1));
    final filter = DiveFilterState(
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2026, 6, 30),
    );
    expect(await idsMatching(filter), {'inside', 'endday'});
  });

  test('tag filter matches ANY selected tag', () async {
    await insertDive('a');
    await insertDive('b');
    await insertDive('c');
    await insertTag('dry');
    await insertTag('night');
    await linkTag('a', 'dry');
    await linkTag('b', 'night');
    expect(await idsMatching(const DiveFilterState(tagIds: ['dry'])), {'a'});
    expect(await idsMatching(const DiveFilterState(tagIds: ['dry', 'night'])), {
      'a',
      'b',
    });
  });

  test('site, depth, rating, favorites axes', () async {
    await insertSite('s1');
    await insertDive(
      'a',
      siteId: 's1',
      maxDepth: 30,
      rating: 5,
      favorite: true,
    );
    await insertDive('b', maxDepth: 10, rating: 2);
    expect(await idsMatching(const DiveFilterState(siteId: 's1')), {'a'});
    expect(await idsMatching(const DiveFilterState(minDepth: 20)), {'a'});
    expect(await idsMatching(const DiveFilterState(minRating: 4)), {'a'});
    expect(await idsMatching(const DiveFilterState(favoritesOnly: true)), {
      'a',
    });
  });

  test(
    'bottom-time filter truncates to whole minutes like Duration.inMinutes',
    () async {
      // 149s = 2 min (truncated); with maxBottomTimeMinutes: 2 it must pass.
      await insertDive('short', bottomTimeSeconds: 149);
      await insertDive('long', bottomTimeSeconds: 600);
      expect(
        await idsMatching(const DiveFilterState(maxBottomTimeMinutes: 2)),
        {'short'},
      );
      expect(
        await idsMatching(const DiveFilterState(minBottomTimeMinutes: 5)),
        {'long'},
      );
    },
  );

  test(
    'parity: apply() and the subquery agree on date + bottom-time edges',
    () async {
      // Build domain dives and matching DB rows, then assert both filter paths
      // return the same ids for the same filter.
      final cases = <(String, DateTime, int)>[
        ('a', DateTime(2026, 6, 30, 23, 0), 149),
        ('b', DateTime(2026, 7, 2), 600),
        ('c', DateTime(2026, 5, 1), 61),
      ];
      for (final (id, date, bt) in cases) {
        await db
            .into(db.dives)
            .insert(
              DivesCompanion(
                id: Value(id),
                diveDateTime: Value(date.millisecondsSinceEpoch),
                bottomTime: Value(bt),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
      }
      final domainDives = cases
          .map(
            (c) => dive_entity.Dive(
              id: c.$1,
              dateTime: c.$2,
              bottomTime: Duration(seconds: c.$3),
            ),
          )
          .toList();

      for (final filter in <DiveFilterState>[
        DiveFilterState(
          startDate: DateTime(2026, 6, 1),
          endDate: DateTime(2026, 6, 30),
        ),
        const DiveFilterState(maxBottomTimeMinutes: 2),
        const DiveFilterState(minBottomTimeMinutes: 2),
      ]) {
        final applied = filter.apply(domainDives).map((d) => d.id).toSet();
        final sqld = await idsMatching(filter);
        expect(sqld, applied, reason: 'mismatch for $filter');
      }
    },
  );
}
