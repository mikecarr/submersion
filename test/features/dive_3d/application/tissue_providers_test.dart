import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_3d/application/tissue_providers.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_surface_builder.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/domain/entities/source_profile.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_providers.dart';
import 'package:submersion/features/dive_log/presentation/providers/gas_switch_providers.dart';

import '../../../helpers/mock_providers.dart';

Dive diveWith(String id, DateTime start) => Dive(
  id: id,
  dateTime: start,
  entryTime: start,
  exitTime: start.add(const Duration(minutes: 40)),
  runtime: const Duration(minutes: 40),
  maxDepth: 30,
);

SourceProfile squareProfile(String id) {
  final points = [
    const DiveProfilePoint(timestamp: 0, depth: 0),
    const DiveProfilePoint(timestamp: 120, depth: 30),
    const DiveProfilePoint(timestamp: 1200, depth: 30),
    const DiveProfilePoint(timestamp: 1400, depth: 0),
  ];
  return SourceProfile(
    sourceId: 'src',
    computerId: null,
    isEdited: false,
    points: points,
  );
}

Future<ProviderContainer> makeContainer({
  required List<Dive> dives,
  Map<String, SourceProfile?> profiles = const {},
}) async {
  final base = await getBaseOverrides();
  final container = ProviderContainer(
    overrides: [
      ...base,
      divesProvider.overrideWith((ref) async => dives),
      for (final dive in dives) ...[
        sourceProfilesProvider(dive.id).overrideWith(
          (ref) async => {
            if (profiles[dive.id] != null) 'src': profiles[dive.id]!,
          },
        ),
        gasSwitchesProvider(dive.id).overrideWith((ref) async => const []),
      ],
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  final base = DateTime.utc(2026, 7, 11, 8);

  test('chain provider derives the repetitive-dive chain', () async {
    final dives = [
      diveWith('a', base),
      diveWith('b', base.add(const Duration(hours: 2))),
    ];
    final container = await makeContainer(dives: dives);
    final chain = await container.read(tissueChainProvider('a').future);
    expect(chain, isNotNull);
    expect(chain!.dives.map((d) => d.id), ['a', 'b']);
    expect(chain.surfaceIntervals.length, 1);
  });

  test('replay provider is null when the dive has no profile', () async {
    final container = await makeContainer(dives: [diveWith('a', base)]);
    final result = await container.read(tissueReplayProvider('a').future);
    expect(result, isNull);
  });

  test('replay + geometry build for a profiled dive', () async {
    final container = await makeContainer(
      dives: [diveWith('a', base)],
      profiles: {'a': squareProfile('a')},
    );
    final result = await container.read(tissueReplayProvider('a').future);
    expect(result, isNotNull);
    expect(result!.columnCount, greaterThan(2));

    final scene = await container.read(
      tissueGeometryProvider((
        diveId: 'a',
        gas: TissueGas.combined,
        colorMode: TissueColorMode.mValue,
        splitHelium: false,
      )).future,
    );
    expect(scene, isNotNull);
    expect(scene!.layers, isNotEmpty);
    expect(scene.scrubPath, isNotNull);
  });
}
