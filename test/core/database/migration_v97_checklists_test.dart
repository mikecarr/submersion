import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';

void main() {
  test('v97 creates the three checklist tables with hlc columns', () async {
    final nativeDb = NativeDatabase.memory(
      setup: (rawDb) {
        rawDb.execute('PRAGMA user_version = 96');
        // Minimal parents so FK references resolve.
        rawDb.execute('''
          CREATE TABLE divers (id TEXT NOT NULL PRIMARY KEY)
        ''');
        rawDb.execute('''
          CREATE TABLE trips (id TEXT NOT NULL PRIMARY KEY)
        ''');
      },
    );
    final db = AppDatabase(nativeDb);
    addTearDown(() => db.close());

    for (final table in [
      'checklist_templates',
      'checklist_template_items',
      'trip_checklist_items',
    ]) {
      final cols = await db.customSelect("PRAGMA table_info('$table')").get();
      final names = cols.map((c) => c.read<String>('name')).toSet();
      expect(names, contains('id'), reason: '$table missing id');
      expect(names, contains('hlc'), reason: '$table missing hlc');
      expect(
        names,
        contains('created_at'),
        reason: '$table missing created_at',
      );
    }

    final templateItemCols = await db
        .customSelect("PRAGMA table_info('checklist_template_items')")
        .get();
    final templateItemNames = templateItemCols
        .map((c) => c.read<String>('name'))
        .toSet();
    expect(templateItemNames, contains('due_offset_days'));
    expect(templateItemNames, contains('sort_order'));

    final tripItemCols = await db
        .customSelect("PRAGMA table_info('trip_checklist_items')")
        .get();
    final tripItemNames = tripItemCols
        .map((c) => c.read<String>('name'))
        .toSet();
    expect(tripItemNames, containsAll(['due_date', 'is_done', 'completed_at']));

    final indexes = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%checklist%'",
        )
        .get();
    final indexNames = indexes.map((r) => r.read<String>('name')).toSet();
    expect(indexNames, contains('idx_trip_checklist_items_trip_id'));
    expect(indexNames, contains('idx_checklist_template_items_template_id'));
  });

  test(
    'recovers databases stranded at v96 by the photo-markers collision',
    () async {
      // Reproduces the user's exact live-DB state: a parallel in-flight
      // feature (photo markers) also claimed schema v96 and already ran
      // against this database, so user_version is 96 and
      // diver_settings.default_show_photo_markers exists, but our checklist
      // tables were never created because our old `if (from < 96)` guard
      // saw from == 96 and skipped. The v97 migration must still create the
      // checklist tables (idempotent DDL) and must not disturb the
      // photo-markers column that already landed.
      final nativeDb = NativeDatabase.memory(
        setup: (rawDb) {
          rawDb.execute('PRAGMA user_version = 96');
          rawDb.execute('''
            CREATE TABLE divers (id TEXT NOT NULL PRIMARY KEY)
          ''');
          rawDb.execute('''
            CREATE TABLE trips (id TEXT NOT NULL PRIMARY KEY)
          ''');
          rawDb.execute('''
            CREATE TABLE diver_settings (
              id TEXT NOT NULL PRIMARY KEY,
              diver_id TEXT NOT NULL,
              default_show_photo_markers INTEGER NOT NULL DEFAULT 0
            )
          ''');
        },
      );
      final db = AppDatabase(nativeDb);
      addTearDown(() => db.close());

      for (final table in [
        'checklist_templates',
        'checklist_template_items',
        'trip_checklist_items',
      ]) {
        final cols = await db.customSelect("PRAGMA table_info('$table')").get();
        expect(cols, isNotEmpty, reason: '$table was not created');
      }

      final diverSettingsCols = await db
          .customSelect("PRAGMA table_info('diver_settings')")
          .get();
      final diverSettingsNames = diverSettingsCols
          .map((c) => c.read<String>('name'))
          .toSet();
      expect(diverSettingsNames, contains('default_show_photo_markers'));
    },
  );

  test('schema version is 97 and the migration list includes it', () {
    expect(AppDatabase.currentSchemaVersion, 97);
    expect(AppDatabase.migrationVersions, contains(97));
  });

  test('fresh database exposes the checklist tables via Drift', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    expect(await db.select(db.checklistTemplates).get(), isEmpty);
    expect(await db.select(db.checklistTemplateItems).get(), isEmpty);
    expect(await db.select(db.tripChecklistItems).get(), isEmpty);
  });
}
