import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/media/data/services/photo_picker_service.dart';
import 'package:submersion/features/media/data/services/trip_media_scanner.dart';
import 'package:submersion/features/media/presentation/helpers/lightroom_scan_helper.dart';
import 'package:submersion/features/media/presentation/providers/media_providers.dart';
import 'package:submersion/features/media/presentation/providers/photo_picker_providers.dart';
import 'package:submersion/features/media/presentation/widgets/scan_results_dialog.dart';
import 'package:submersion/features/trips/domain/entities/trip.dart';
import 'package:submersion/features/trips/presentation/providers/trip_media_providers.dart';
import 'package:submersion/features/trips/presentation/providers/trip_providers.dart';
import 'package:submersion/features/trips/presentation/widgets/dive_assignment_dialog.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Scan the device gallery for photos taken during the trip and link them to
/// the trip's dives.
Future<void> scanGalleryForTripPhotos(
  BuildContext context,
  WidgetRef ref,
  String tripId,
  Trip trip,
) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final dives = await ref.read(divesForTripProvider(tripId).future);

    if (dives.isEmpty) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.trips_detail_scan_addDivesFirst)),
        );
      }
      return;
    }

    final mediaByDive = await ref.read(mediaForTripProvider(tripId).future);
    final existingIds = <String>{};
    for (final mediaList in mediaByDive.values) {
      for (final item in mediaList) {
        if (item.platformAssetId != null) {
          existingIds.add(item.platformAssetId!);
        }
      }
    }

    final photoPickerService = ref.read(photoPickerServiceProvider);
    final result = await TripMediaScanner.scanGalleryForTrip(
      dives: dives,
      tripStartDate: trip.startDate,
      tripEndDate: trip.endDate,
      existingAssetIds: existingIds,
      photoPickerService: photoPickerService,
    );

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.trips_detail_scan_accessDenied)),
      );
      return;
    }

    final dialogResult = await showScanResultsDialog(
      context: context,
      scanResult: result,
    );

    if (dialogResult.confirmed != true) return;
    if (!context.mounted) return;

    await _importPhotos(context, ref, tripId, dialogResult.selectedPhotos);
  } catch (e) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.trips_detail_scan_errorScanning('$e')),
        ),
      );
    }
  }
}

Future<void> _importPhotos(
  BuildContext context,
  WidgetRef ref,
  String tripId,
  Map<Dive, List<AssetInfo>> photosByDive,
) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Text(context.l10n.trips_detail_scan_linkingPhotos),
        ],
      ),
    ),
  );

  try {
    final importService = ref.read(mediaImportServiceProvider);
    int totalImported = 0;

    for (final entry in photosByDive.entries) {
      final dive = entry.key;
      final assets = entry.value;

      final result = await importService.importPhotosForDive(
        selectedAssets: assets,
        dive: dive,
      );

      totalImported += result.imported.length;

      ref.invalidate(mediaForDiveProvider(dive.id));
      ref.invalidate(mediaCountForDiveProvider(dive.id));
    }

    ref.invalidate(mediaForTripProvider(tripId));
    ref.invalidate(mediaCountForTripProvider(tripId));
    ref.invalidate(flatMediaListForTripProvider(tripId));

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // Dismiss progress

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.trips_detail_scan_linkedPhotos(totalImported),
        ),
      ),
    );
  } catch (e) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.trips_detail_scan_errorLinking('$e')),
        ),
      );
    }
  }
}

/// Scan the diver's Lightroom catalog for photos matching the trip's dives.
Future<void> scanLightroomForTrip(
  BuildContext context,
  WidgetRef ref,
  String tripId,
) async {
  final dives = await ref.read(divesForTripProvider(tripId).future);
  if (!context.mounted) return;
  if (dives.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.trips_detail_scan_addDivesFirst)),
    );
    return;
  }
  await runLightroomScan(context, ref, dives);
}

/// Find dives whose date falls within the trip range and offer to assign them.
Future<void> scanForTripDives(
  BuildContext context,
  WidgetRef ref,
  Trip trip,
) async {
  if (trip.diverId == null) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final candidates = await ref
        .read(tripRepositoryProvider)
        .findCandidateDivesForTrip(
          tripId: trip.id,
          startDate: trip.startDate,
          endDate: trip.endDate,
          diverId: trip.diverId!,
        );

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.trips_diveScan_noMatches)),
      );
      return;
    }

    final selectedIds = await showDiveAssignmentDialog(
      context: context,
      candidates: candidates,
    );

    if (selectedIds == null || selectedIds.isEmpty || !context.mounted) {
      return;
    }

    final oldTripIds = candidates
        .where((c) => selectedIds.contains(c.dive.id) && !c.isUnassigned)
        .map((c) => c.currentTripId!)
        .toSet();

    await ref
        .read(tripListNotifierProvider.notifier)
        .assignDivesToTrip(selectedIds, trip.id, oldTripIds: oldTripIds);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.trips_diveScan_added(selectedIds.length)),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.trips_diveScan_error('$e'))),
      );
    }
  }
}
