import 'package:submersion/core/utils/geo_math.dart';
import 'package:submersion/features/dive_sites/domain/entities/dive_site.dart';
import 'package:submersion/features/dive_sites/domain/matching/match_candidate.dart';
import 'package:submersion/features/dive_sites/domain/matching/match_thresholds.dart';
import 'package:submersion/features/dive_sites/domain/matching/site_match_outcome.dart';

/// Matches one dive GPS [point] against [candidates].
///
/// Rules, in order:
/// 1. Rank candidates by distance; keep those within the outer radius.
///    None -> [NoMatch].
/// 2. Pool selection: if any existing site is within the inner radius, the
///    auto-decision considers only those (existing-site precedence — never
///    auto-create a bundled duplicate when the user already has a site here);
///    otherwise consider every candidate within the inner radius.
/// 3. The nearest in the pool is a clear [AutoMatch] when it has no in-pool
///    competitor, or the runner-up is farther by at least the separation
///    margin. Otherwise -> [Suggested] (all in-range candidates, both pools).
SiteMatchOutcome matchDive({
  required GeoPoint point,
  required List<MatchCandidate> candidates,
  required MatchThresholds thresholds,
}) {
  final ranked =
      candidates
          .map((c) => RankedCandidate(c, distanceMeters(point, c.location)))
          .toList()
        ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

  final inRange = ranked
      .where((r) => r.distanceMeters <= thresholds.outerRadiusMeters)
      .toList();
  if (inRange.isEmpty) return const NoMatch();

  final innerExisting = inRange
      .where(
        (r) =>
            r.candidate.isExisting &&
            r.distanceMeters <= thresholds.innerRadiusMeters,
      )
      .toList();
  final innerAny = inRange
      .where((r) => r.distanceMeters <= thresholds.innerRadiusMeters)
      .toList();

  final pool = innerExisting.isNotEmpty ? innerExisting : innerAny;
  if (pool.isEmpty) return Suggested(inRange);

  final nearest = pool.first;
  final clear =
      pool.length == 1 ||
      (pool[1].distanceMeters - nearest.distanceMeters) >=
          thresholds.separationMeters;

  if (clear) {
    return AutoMatch(
      siteId: nearest.candidate.id,
      isExisting: nearest.candidate.isExisting,
      distanceMeters: nearest.distanceMeters,
    );
  }
  return Suggested(inRange);
}
