import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
  });

  tearDown(() async {
    await db.close();
  });

  test('gps_tracks table accepts a row round-trip', () async {
    await db
        .into(db.gpsTracks)
        .insert(
          GpsTracksCompanion.insert(
            id: 'track-1',
            startTime: 1700000000000,
            createdAt: 1700000000000,
            updatedAt: 1700000000000,
          ),
        );
    final row = await (db.select(
      db.gpsTracks,
    )..where((t) => t.id.equals('track-1'))).getSingle();
    expect(row.endTime, isNull);
    expect(row.pointCount, 0);
  });

  test('gps_track_points_local accepts buffer rows', () async {
    await db
        .into(db.gpsTrackPointsLocal)
        .insert(
          GpsTrackPointsLocalCompanion.insert(
            trackId: 'track-1',
            timestamp: 1700000000,
            latitude: 20.5,
            longitude: -87.2,
          ),
        );
    final rows = await db.select(db.gpsTrackPointsLocal).get();
    expect(rows.single.latitude, 20.5);
  });
}
