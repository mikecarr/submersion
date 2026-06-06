import 'package:drift/drift.dart';

import 'package:submersion/core/data/repositories/sync_repository.dart';
import 'package:submersion/core/database/database.dart';
import 'package:submersion/core/services/database_service.dart';
import 'package:submersion/core/services/logger_service.dart';
import 'package:submersion/core/services/sync/sync_event_bus.dart';
import 'package:submersion/features/divers/domain/entities/diver.dart'
    as domain;

/// A set of diver profiles that appear to be the same person (same normalized
/// name), with a recommended keeper. Surfaced after sync so the user can
/// confirm a merge.
class DuplicateDiverGroup {
  /// The profile to keep: the default diver if one is in the group, else the
  /// oldest by createdAt (most likely to hold the real history).
  final domain.Diver keeper;

  /// The other profiles, all merge candidates into [keeper].
  final List<domain.Diver> duplicates;

  const DuplicateDiverGroup({required this.keeper, required this.duplicates});

  String get displayName => keeper.name;
}

/// Merges two diver profiles that represent the same person.
///
/// The canonical case: each device auto-creates its own owner diver (with a
/// distinct UUID) at first launch, then sync brings both forward, so the user
/// ends up with two profiles named the same. Merging repoints every record
/// that references the duplicate onto the keeper and deletes the duplicate.
///
/// The set of tables to repoint is discovered from the live schema (every
/// table with a `diver_id` column) rather than hardcoded, so a future table
/// that gains a `diver_id` is handled automatically.
class DiverMergeRepository {
  AppDatabase get _db => DatabaseService.instance.database;
  final SyncRepository _syncRepository = SyncRepository();
  final _log = LoggerService.forClass(DiverMergeRepository);

  /// Tables holding per-device or per-(diver,view-mode) configuration that
  /// should not accumulate across devices when divers are merged. The keeper's
  /// rows win and the duplicate's rows are dropped rather than repointed.
  ///
  /// (Note: there are no unique constraints on `diver_id` in these tables, so
  /// repointing would not crash -- it would just leave the keeper with two of
  /// every config row, which is worse UX than the keeper's existing config
  /// winning unconditionally for these auto-generated layouts/settings.)
  ///
  /// `field_presets` is intentionally NOT in this set: those are user-named
  /// custom presets and losing them would be real data loss; they are
  /// repointed onto the keeper instead.
  static const _singletonConfigTables = {'diver_settings', 'view_configs'};

  /// Repoint all references from [duplicateId] to [keeperId], then delete the
  /// duplicate diver. Idempotent-safe to call once per duplicate.
  Future<void> mergeDivers({
    required String keeperId,
    required String duplicateId,
  }) async {
    if (keeperId == duplicateId) {
      throw ArgumentError('keeperId and duplicateId must differ');
    }
    _log.info('Merging diver $duplicateId into $keeperId');

    final tables = await _tablesWithDiverId();
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.transaction(() async {
      // Deferred FK checks: repointing in catalog order may briefly touch
      // rows whose FK targets are validated at commit, not per-statement.
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');

      for (final table in tables) {
        if (_singletonConfigTables.contains(table)) {
          // Keeper's config wins; drop the duplicate's.
          await _logRowDeletions(table, duplicateId);
          await _db.customStatement('DELETE FROM "$table" WHERE diver_id = ?', [
            duplicateId,
          ]);
        } else {
          // Additive data: repoint onto the keeper and mark pending for sync.
          await _markRowsPending(table, duplicateId, now);
          await _db.customStatement(
            'UPDATE "$table" SET diver_id = ? WHERE diver_id = ?',
            [keeperId, duplicateId],
          );
        }
      }

      // Finally remove the duplicate diver itself, and log the deletion
      // inside the same transaction so the local DB state and the sync
      // tombstone commit atomically (matches the buddy-merge pattern; a
      // crash between the two would otherwise leave the duplicate gone
      // locally but unable to propagate the delete to other devices).
      await (_db.delete(
        _db.divers,
      )..where((t) => t.id.equals(duplicateId))).go();
      await _syncRepository.logDeletion(
        entityType: 'divers',
        recordId: duplicateId,
      );
    });

    SyncEventBus.notifyLocalChange();
    _log.info('Merge complete: $duplicateId -> $keeperId');
  }

  /// All tables (except `divers`) that have a `diver_id` column.
  Future<List<String>> _tablesWithDiverId() async {
    final rows = await _db
        .customSelect(
          "SELECT m.name AS tbl FROM sqlite_master m "
          "JOIN pragma_table_info(m.name) p "
          "WHERE m.type = 'table' AND p.name = 'diver_id' "
          "AND m.name != 'divers'",
        )
        .get();
    return rows.map((r) => r.read<String>('tbl')).toList();
  }

  /// Maps a SQLite table name to the sync entityType string used by the
  /// serializer / deletion log. Most are lowerCamelCase of the snake_case
  /// table name; the map covers the handful that differ.
  static const _tableToEntityType = {
    'dives': 'dives',
    'dive_sites': 'diveSites',
    'dive_centers': 'diveCenters',
    'dive_types': 'diveTypes',
    'dive_computers': 'diveComputers',
    'tank_presets': 'tankPresets',
    'equipment_sets': 'equipmentSets',
    'diver_settings': 'diverSettings',
    'view_configs': 'viewConfigs',
    'field_presets': 'fieldPresets',
    'trips': 'trips',
    'equipment': 'equipment',
    'buddies': 'buddies',
    'certifications': 'certifications',
    'tags': 'tags',
    'courses': 'courses',
  };

  String _entityTypeFor(String table) =>
      _tableToEntityType[table] ?? _toLowerCamel(table);

  static String _toLowerCamel(String snake) {
    final parts = snake.split('_');
    return parts.first +
        parts
            .skip(1)
            .map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1))
            .join();
  }

  /// Mark every row in [table] owned by [diverId] as pending sync (so the
  /// repoint propagates to other devices).
  Future<void> _markRowsPending(String table, String diverId, int now) async {
    final entityType = _entityTypeFor(table);
    final ids = await _rowIds(table, diverId);
    for (final id in ids) {
      await _syncRepository.markRecordPending(
        entityType: entityType,
        recordId: id,
        localUpdatedAt: now,
      );
    }
  }

  /// Log a deletion for every row in [table] owned by [diverId].
  Future<void> _logRowDeletions(String table, String diverId) async {
    final entityType = _entityTypeFor(table);
    final ids = await _rowIds(table, diverId);
    for (final id in ids) {
      await _syncRepository.logDeletion(entityType: entityType, recordId: id);
    }
  }

  Future<List<String>> _rowIds(String table, String diverId) async {
    final rows = await _db
        .customSelect(
          'SELECT id FROM "$table" WHERE diver_id = ?',
          variables: [Variable.withString(diverId)],
        )
        .get();
    return rows.map((r) => r.read<String>('id')).toList();
  }

  /// Group [divers] that share a normalized (trimmed, case-insensitive) name
  /// into [DuplicateDiverGroup]s. Only groups with 2+ members are returned.
  ///
  /// Within each group the keeper is the default diver if present, otherwise
  /// the oldest by createdAt. Pure function (no DB) so it is trivially
  /// unit-testable and reusable by a post-sync detection provider.
  static List<DuplicateDiverGroup> findDuplicateGroups(
    List<domain.Diver> divers,
  ) {
    final byName = <String, List<domain.Diver>>{};
    for (final diver in divers) {
      final key = diver.name.trim().toLowerCase();
      if (key.isEmpty) continue;
      byName.putIfAbsent(key, () => []).add(diver);
    }

    final groups = <DuplicateDiverGroup>[];
    for (final members in byName.values) {
      if (members.length < 2) continue;
      final sorted = [...members]
        ..sort((a, b) {
          // Default diver first, then oldest createdAt.
          if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
          return a.createdAt.compareTo(b.createdAt);
        });
      groups.add(
        DuplicateDiverGroup(
          keeper: sorted.first,
          duplicates: sorted.sublist(1),
        ),
      );
    }
    return groups;
  }
}
