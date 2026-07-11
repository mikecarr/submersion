import 'package:submersion/features/dive_log/domain/entities/dive.dart';

/// Derives the repetitive-dive chain a dive belongs to: the run of dives
/// linked by surface intervals under [maxInterval]. Pure; timing comes from
/// entry/exit times with dateTime + runtime/bottomTime fallbacks.
class TissueChainDeriver {
  static const Duration maxInterval = Duration(hours: 24);

  static DateTime startOf(Dive d) => d.entryTime ?? d.dateTime;

  static DateTime endOf(Dive d) {
    final s = startOf(d);
    final dur = d.runtime ?? d.bottomTime ?? Duration.zero;
    return d.exitTime ?? s.add(dur);
  }

  /// Ordered chain (earliest first) around [entryDiveId], with the surface
  /// interval in seconds between each consecutive pair. Empty when the dive
  /// is not found.
  static ({List<Dive> dives, List<int> surfaceIntervals}) derive(
    List<Dive> allDives,
    String entryDiveId, {
    Duration maxInterval = TissueChainDeriver.maxInterval,
  }) {
    final sorted = [...allDives]
      ..sort((a, b) => startOf(a).compareTo(startOf(b)));
    final idx = sorted.indexWhere((d) => d.id == entryDiveId);
    if (idx < 0) {
      return (dives: const <Dive>[], surfaceIntervals: const <int>[]);
    }

    bool linked(Dive earlier, Dive later) {
      final gap = startOf(later).difference(endOf(earlier));
      return gap >= Duration.zero && gap < maxInterval;
    }

    var lo = idx, hi = idx;
    while (lo > 0 && linked(sorted[lo - 1], sorted[lo])) {
      lo--;
    }
    while (hi < sorted.length - 1 && linked(sorted[hi], sorted[hi + 1])) {
      hi++;
    }

    final chain = sorted.sublist(lo, hi + 1);
    final intervals = <int>[
      for (var i = 0; i < chain.length - 1; i++)
        startOf(
          chain[i + 1],
        ).difference(endOf(chain[i])).inSeconds.clamp(0, 1 << 30),
    ];
    return (dives: chain, surfaceIntervals: intervals);
  }
}
