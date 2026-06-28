import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_sites/data/services/dive_site_api_service.dart';
import 'package:submersion/features/dive_sites/presentation/providers/site_providers.dart';

/// All built-in (bundled) dive sites with coordinates.
/// Static for the app lifetime; loaded once via the service cache.
final builtInSitesProvider = FutureProvider<List<ExternalDiveSite>>((
  ref,
) async {
  final service = ref.watch(diveSiteApiServiceProvider);
  return service.allSitesWithCoordinates();
});

/// Whether built-in site markers are shown on the Sites map.
/// In-memory only (matches the heat-map toggle convention); resets each launch.
final showBuiltInSitesProvider = StateProvider<bool>((ref) => false);
