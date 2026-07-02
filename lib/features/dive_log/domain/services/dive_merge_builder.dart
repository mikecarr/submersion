import '../entities/dive.dart';

/// Why a merge was rejected outright (neither sequential nor overlapping).
enum DiveMergeInvalidReason { tooFewDives, mixedDivers }

/// One inter-dive surface gap on the merged timeline.
class MergeGap {
  const MergeGap({
    required this.afterDiveId,
    required this.beforeDiveId,
    required this.startSeconds,
    required this.endSeconds,
  });

  /// The gap follows this source dive.
  final String afterDiveId;

  /// The gap precedes this source dive.
  final String beforeDiveId;

  /// Seconds from the merged dive's start.
  final int startSeconds;
  final int endSeconds;

  Duration get duration => Duration(seconds: endSeconds - startSeconds);
}

sealed class DiveMergeClassification {
  const DiveMergeClassification();
}

class MergeInvalid extends DiveMergeClassification {
  const MergeInvalid(this.reason);
  final DiveMergeInvalidReason reason;
}

/// Any pair of dives overlaps in time — these look like the same dive from
/// multiple computers (future feature), not a sequential combine.
class MergeOverlapping extends DiveMergeClassification {
  const MergeOverlapping();
}

class MergeSequential extends DiveMergeClassification {
  const MergeSequential({required this.sortedDives, required this.gaps});
  final List<Dive> sortedDives;
  final List<MergeGap> gaps;
}

class DiveMergeBuilder {
  const DiveMergeBuilder();

  DiveMergeClassification classify(List<Dive> dives) {
    if (dives.length < 2) {
      return const MergeInvalid(DiveMergeInvalidReason.tooFewDives);
    }
    if (dives.map((d) => d.diverId).toSet().length > 1) {
      return const MergeInvalid(DiveMergeInvalidReason.mixedDivers);
    }
    final sorted = [...dives]
      ..sort((a, b) => a.effectiveEntryTime.compareTo(b.effectiveEntryTime));
    final mergedStart = sorted.first.effectiveEntryTime;
    final gaps = <MergeGap>[];
    for (var i = 0; i < sorted.length - 1; i++) {
      final prev = sorted[i];
      final next = sorted[i + 1];
      // A dive with no derivable duration is treated as zero-length: it has
      // no profile samples, so nothing can overlap it. Deliberate (#449
      // review).
      final prevEnd = prev.effectiveEntryTime.add(
        prev.effectiveRuntime ?? Duration.zero,
      );
      if (next.effectiveEntryTime.isBefore(prevEnd)) {
        return const MergeOverlapping();
      }
      gaps.add(
        MergeGap(
          afterDiveId: prev.id,
          beforeDiveId: next.id,
          startSeconds: prevEnd.difference(mergedStart).inSeconds,
          endSeconds: next.effectiveEntryTime.difference(mergedStart).inSeconds,
        ),
      );
    }
    return MergeSequential(sortedDives: sorted, gaps: gaps);
  }
}
