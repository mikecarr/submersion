import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_chain_deriver.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';

Dive diveAt(
  String id,
  DateTime start, {
  Duration runtime = const Duration(minutes: 40),
}) => Dive(
  id: id,
  dateTime: start,
  entryTime: start,
  exitTime: start.add(runtime),
  runtime: runtime,
);

void main() {
  final base = DateTime.utc(2026, 7, 11, 8);

  test('chains dives within the interval window', () {
    final dives = [
      diveAt('a', base),
      diveAt('b', base.add(const Duration(hours: 2))), // ~80 min SI
      diveAt('c', base.add(const Duration(hours: 4))),
    ];
    final chain = TissueChainDeriver.derive(dives, 'b');
    expect(chain.dives.map((d) => d.id), ['a', 'b', 'c']);
    expect(chain.surfaceIntervals.length, 2);
    // SI between a (ends 08:40) and b (starts 10:00) = 80 min = 4800 s.
    expect(chain.surfaceIntervals.first, 80 * 60);
  });

  test('breaks the chain across a gap of 24h or more', () {
    final dives = [
      diveAt('a', base),
      diveAt('b', base.add(const Duration(hours: 25))), // next day
    ];
    final fromA = TissueChainDeriver.derive(dives, 'a');
    expect(fromA.dives.map((d) => d.id), ['a']);
    expect(fromA.surfaceIntervals, isEmpty);
  });

  test('a single dive with no neighbors is its own chain', () {
    final chain = TissueChainDeriver.derive([diveAt('solo', base)], 'solo');
    expect(chain.dives.single.id, 'solo');
  });

  test('empty when the entry dive is not present', () {
    final chain = TissueChainDeriver.derive([diveAt('a', base)], 'missing');
    expect(chain.dives, isEmpty);
  });

  test('boundary: 23h links, 24h+ does not', () {
    final in23 = TissueChainDeriver.derive([
      diveAt('a', base, runtime: Duration.zero),
      diveAt('b', base.add(const Duration(hours: 23))),
    ], 'a');
    expect(in23.dives.length, 2);

    final out25 = TissueChainDeriver.derive([
      diveAt('a', base, runtime: Duration.zero),
      diveAt('b', base.add(const Duration(hours: 25))),
    ], 'a');
    expect(out25.dives.length, 1);
  });
}
