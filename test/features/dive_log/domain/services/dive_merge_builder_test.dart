import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/domain/services/dive_merge_builder.dart';

Dive dive(
  String id, {
  DateTime? entry,
  int runtimeMin = 30,
  String? diverId = 'diver1',
  List<DiveProfilePoint> profile = const [],
}) => Dive(
  id: id,
  diverId: diverId,
  dateTime: entry ?? DateTime.utc(2026, 7, 1, 9),
  entryTime: entry ?? DateTime.utc(2026, 7, 1, 9),
  runtime: Duration(minutes: runtimeMin),
  profile: profile,
);

void main() {
  const builder = DiveMergeBuilder();

  group('classify', () {
    test('fewer than 2 dives is invalid', () {
      final result = builder.classify([dive('a')]);
      expect(result, isA<MergeInvalid>());
      expect(
        (result as MergeInvalid).reason,
        DiveMergeInvalidReason.tooFewDives,
      );
    });

    test('mixed divers is invalid', () {
      final result = builder.classify([
        dive('a', entry: DateTime.utc(2026, 7, 1, 9)),
        dive('b', entry: DateTime.utc(2026, 7, 1, 11), diverId: 'diver2'),
      ]);
      expect(result, isA<MergeInvalid>());
      expect(
        (result as MergeInvalid).reason,
        DiveMergeInvalidReason.mixedDivers,
      );
    });

    test('overlapping dives are classified overlapping', () {
      // a runs 09:00-09:30, b starts 09:15 -> overlap
      final result = builder.classify([
        dive('a', entry: DateTime.utc(2026, 7, 1, 9)),
        dive('b', entry: DateTime.utc(2026, 7, 1, 9, 15)),
      ]);
      expect(result, isA<MergeOverlapping>());
    });

    test('sequential dives sort chronologically and report the gap', () {
      // b: 10:00-10:20, a: 09:00-09:30 -> sorted a,b; gap 09:30-10:00
      final result = builder.classify([
        dive('b', entry: DateTime.utc(2026, 7, 1, 10), runtimeMin: 20),
        dive('a', entry: DateTime.utc(2026, 7, 1, 9), runtimeMin: 30),
      ]);
      expect(result, isA<MergeSequential>());
      final seq = result as MergeSequential;
      expect(seq.sortedDives.map((d) => d.id), ['a', 'b']);
      expect(seq.gaps, hasLength(1));
      expect(seq.gaps.single.afterDiveId, 'a');
      expect(seq.gaps.single.beforeDiveId, 'b');
      expect(seq.gaps.single.startSeconds, 30 * 60);
      expect(seq.gaps.single.endSeconds, 60 * 60);
      expect(seq.gaps.single.duration, const Duration(minutes: 30));
    });

    test('touching dives (gap == 0) are sequential with a zero gap', () {
      final result = builder.classify([
        dive('a', entry: DateTime.utc(2026, 7, 1, 9), runtimeMin: 60),
        dive('b', entry: DateTime.utc(2026, 7, 1, 10)),
      ]);
      expect(result, isA<MergeSequential>());
      expect((result as MergeSequential).gaps.single.duration, Duration.zero);
    });
  });
}
