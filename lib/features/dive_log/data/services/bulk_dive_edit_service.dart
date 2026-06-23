import 'package:submersion/core/database/database.dart';
import 'package:submersion/core/services/database_service.dart';
import 'package:submersion/core/services/sync/sync_event_bus.dart';
import 'package:submersion/features/buddies/data/repositories/buddy_repository.dart';
import 'package:submersion/features/buddies/domain/entities/buddy.dart';
import 'package:submersion/features/dive_log/data/repositories/dive_repository_impl.dart';
import 'package:submersion/features/dive_log/domain/entities/bulk_edit_request.dart';
import 'package:submersion/features/dive_log/domain/entities/bulk_edit_snapshot.dart';
import 'package:submersion/features/marine_life/data/repositories/species_repository.dart';

/// Orchestrates a bulk edit across repositories in a single transaction.
///
/// `DiveTank`, `DiveWeight`, `Sighting` referenced here are the Drift row
/// classes (from database.dart); `BuddyWithRole` is the domain type.
class BulkDiveEditService {
  BulkDiveEditService(this._diveRepo, this._buddyRepo, this._speciesRepo);

  final DiveRepository _diveRepo;
  final BuddyRepository _buddyRepo;
  final SpeciesRepository _speciesRepo;

  AppDatabase get _db => DatabaseService.instance.database;

  /// Apply [req] to every dive in [req.diveIds] inside one transaction,
  /// capturing the prior state first. Fires a single local-change notification.
  Future<BulkEditSnapshot> apply(BulkEditRequest req) async {
    final ids = req.diveIds;
    if (ids.isEmpty) {
      return const BulkEditSnapshot(priorDiveRows: []);
    }

    // Capture prior state before mutating (reads outside the transaction).
    final priorDiveRows = await (_db.select(
      _db.dives,
    )..where((t) => t.id.isIn(ids))).get();

    Map<String, List<String>>? priorTagIds;
    Map<String, List<String>>? priorEquipmentIds;
    Map<String, List<BuddyWithRole>>? priorBuddies;
    Map<String, List<DiveTank>>? priorTanks;
    Map<String, List<DiveWeight>>? priorWeights;
    Map<String, List<Sighting>>? priorSightings;

    for (final op in req.ops) {
      switch (op) {
        case TagsOp():
          final rows = await (_db.select(
            _db.diveTags,
          )..where((t) => t.diveId.isIn(ids))).get();
          priorTagIds = {for (final id in ids) id: <String>[]};
          for (final r in rows) {
            priorTagIds[r.diveId]!.add(r.tagId);
          }
        case EquipmentOp():
          final rows = await (_db.select(
            _db.diveEquipment,
          )..where((t) => t.diveId.isIn(ids))).get();
          priorEquipmentIds = {for (final id in ids) id: <String>[]};
          for (final r in rows) {
            priorEquipmentIds[r.diveId]!.add(r.equipmentId);
          }
        case BuddiesOp():
          priorBuddies = {
            for (final id in ids) id: await _buddyRepo.getBuddiesForDive(id),
          };
        case TanksOp():
          final rows = await (_db.select(
            _db.diveTanks,
          )..where((t) => t.diveId.isIn(ids))).get();
          priorTanks = {for (final id in ids) id: <DiveTank>[]};
          for (final r in rows) {
            priorTanks[r.diveId]!.add(r);
          }
        case WeightsOp():
          final rows = await (_db.select(
            _db.diveWeights,
          )..where((t) => t.diveId.isIn(ids))).get();
          priorWeights = {for (final id in ids) id: <DiveWeight>[]};
          for (final r in rows) {
            priorWeights[r.diveId]!.add(r);
          }
        case SightingsOp():
          final rows = await (_db.select(
            _db.sightings,
          )..where((t) => t.diveId.isIn(ids))).get();
          priorSightings = {for (final id in ids) id: <Sighting>[]};
          for (final r in rows) {
            priorSightings[r.diveId]!.add(r);
          }
      }
    }

    await _db.transaction(() async {
      if (req.hasScalarChanges) {
        await _diveRepo.bulkUpdateFields(ids, req.scalars);
      }
      if (req.notesAppend != null && req.notesAppend!.isNotEmpty) {
        await _diveRepo.bulkAppendNotes(ids, req.notesAppend!);
      }
      for (final op in req.ops) {
        await _applyOp(ids, op);
      }
    });

    SyncEventBus.notifyLocalChange();

    return BulkEditSnapshot(
      priorDiveRows: priorDiveRows,
      priorTagIds: priorTagIds,
      priorEquipmentIds: priorEquipmentIds,
      priorBuddies: priorBuddies,
      priorTanks: priorTanks,
      priorWeights: priorWeights,
      priorSightings: priorSightings,
    );
  }

  Future<void> _applyOp(List<String> ids, BulkCollectionOp op) async {
    switch (op) {
      case TagsOp(:final mode, :final tagIds):
        switch (mode) {
          case BulkCollectionMode.add:
            await _diveRepo.bulkAddTags(ids, tagIds);
          case BulkCollectionMode.remove:
            await _diveRepo.bulkRemoveTags(ids, tagIds);
          case BulkCollectionMode.replace:
            await _diveRepo.bulkReplaceTags(ids, tagIds);
        }
      case EquipmentOp(:final mode, :final equipmentIds):
        switch (mode) {
          case BulkCollectionMode.add:
            await _diveRepo.bulkAddEquipment(ids, equipmentIds);
          case BulkCollectionMode.remove:
            await _diveRepo.bulkRemoveEquipment(ids, equipmentIds);
          case BulkCollectionMode.replace:
            await _diveRepo.bulkReplaceEquipment(ids, equipmentIds);
        }
      case BuddiesOp(:final mode, :final buddies):
        switch (mode) {
          case BulkCollectionMode.add:
            await _buddyRepo.bulkAddBuddies(ids, buddies);
          case BulkCollectionMode.remove:
            await _buddyRepo.bulkRemoveBuddies(
              ids,
              buddies.map((b) => b.buddy.id).toList(),
            );
          case BulkCollectionMode.replace:
            await _buddyRepo.bulkReplaceBuddies(ids, buddies);
        }
      case TanksOp(:final mode, :final tanks, :final onlyIfEmpty):
        if (mode == BulkCollectionMode.replace) {
          await _diveRepo.bulkReplaceTanks(ids, tanks);
        } else {
          for (final tank in tanks) {
            await _diveRepo.bulkAddTank(ids, tank, onlyIfEmpty: onlyIfEmpty);
          }
        }
      case WeightsOp(:final mode, :final weights):
        if (mode == BulkCollectionMode.replace) {
          await _diveRepo.bulkReplaceWeights(ids, weights);
        } else {
          await _diveRepo.bulkAddWeights(ids, weights);
        }
      case SightingsOp(:final mode, :final sightings):
        if (mode == BulkCollectionMode.replace) {
          await _speciesRepo.bulkReplaceSightings(ids, sightings);
        } else {
          await _speciesRepo.bulkAddSightings(ids, sightings);
        }
    }
  }
}
