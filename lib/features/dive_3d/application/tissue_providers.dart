import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:submersion/core/deco/constants/buhlmann_coefficients.dart';
import 'package:submersion/core/deco/entities/dive_environment.dart';
import 'package:submersion/features/dive_3d/domain/scene_3d.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_chain.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_chain_deriver.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_geometry_service.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_replay_result.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_replay_service.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_surface_builder.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/domain/entities/gas_switch.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_providers.dart';
import 'package:submersion/features/dive_log/presentation/providers/gas_switch_providers.dart';
import 'package:submersion/features/dive_log/presentation/widgets/profile_decimator.dart';

/// Cap on replay columns per dive; tissue kinetics are far slower than
/// profile sampling, so ~15 s spacing on an hour dive is plenty.
const int _maxColumnsPerDive = 240;

/// Default gradient factors when a dive records none.
const int _defaultGfLow = 30;
const int _defaultGfHigh = 70;

/// The repetitive-dive chain a dive belongs to.
final tissueChainProvider = FutureProvider.family<TissueDiveChain?, String>((
  ref,
  diveId,
) async {
  final all = await ref.watch(divesProvider.future);
  final derived = TissueChainDeriver.derive(all, diveId);
  if (derived.dives.isEmpty) return null;
  return TissueDiveChain(
    dives: derived.dives,
    surfaceIntervals: derived.surfaceIntervals,
  );
});

/// Per-sample tissue loading across the chain. Null when the viewed dive
/// has no usable profile.
final tissueReplayProvider = FutureProvider.family<TissueReplayResult?, String>(
  (ref, diveId) async {
    final chain = await ref.watch(tissueChainProvider(diveId).future);
    if (chain == null) return null;

    final entry = chain.dives.firstWhere((d) => d.id == diveId);
    final entryProfile = await ref.watch(
      _diveProfilePointsProvider(diveId).future,
    );
    if (entryProfile.length < 2) return null;

    final diveInputs = <TissueDiveInput>[];
    for (final dive in chain.dives) {
      final points = dive.id == diveId
          ? entryProfile
          : await ref.watch(_diveProfilePointsProvider(dive.id).future);
      final switches = await ref.watch(gasSwitchesProvider(dive.id).future);
      diveInputs.add(_diveInputFor(dive, points, switches));
    }

    final environment = DiveEnvironment.forConditions(
      altitudeMeters: entry.altitude,
      waterType: entry.waterType,
      surfacePressureBar: entry.surfacePressure,
    );
    final input = TissueChainInput(
      dives: diveInputs,
      surfaceIntervalSeconds: chain.surfaceIntervals,
      gfLow: (entry.gradientFactorLow ?? _defaultGfLow) / 100,
      gfHigh: (entry.gradientFactorHigh ?? _defaultGfHigh) / 100,
      environment: environment,
    );

    final columns = diveInputs.fold<int>(0, (a, d) => a + d.times.length);
    if (columns < 2000) return const TissueReplayService().replay(input);
    return compute(_replayIsolate, input);
  },
);

typedef TissueGeometryKey = ({
  String diveId,
  TissueGas gas,
  TissueColorMode colorMode,
  bool splitHelium,
});

/// The renderable tissue scene per (dive, gas, color mode, split).
final tissueGeometryProvider =
    FutureProvider.family<Scene3d?, TissueGeometryKey>((ref, key) async {
      final result = await ref.watch(tissueReplayProvider(key.diveId).future);
      if (result == null) return null;
      return const TissueGeometryService().build(
        result,
        gas: key.gas,
        colorMode: key.colorMode,
        splitHelium: key.splitHelium,
      );
    });

TissueReplayResult _replayIsolate(TissueChainInput input) =>
    const TissueReplayService().replay(input);

/// Primary-source profile points for a dive.
final _diveProfilePointsProvider =
    FutureProvider.family<List<DiveProfilePoint>, String>((ref, diveId) async {
      final sources = await ref.watch(sourceProfilesProvider(diveId).future);
      return sources.values.firstOrNull?.points ?? const [];
    });

TissueDiveInput _diveInputFor(
  Dive dive,
  List<DiveProfilePoint> points,
  List<GasSwitchWithTank> switches,
) {
  final sorted = points.length >= 2
      ? ([...points]..sort((a, b) => a.timestamp - b.timestamp))
      : _squareProfile(dive);
  final indices = decimateSeriesIndices([
    for (final p in sorted) p.depth,
  ], targetPoints: _maxColumnsPerDive);
  return TissueDiveInput(
    times: [for (final i in indices) sorted[i].timestamp.toDouble()],
    depths: [for (final i in indices) sorted[i].depth],
    gasLegs: _gasLegsFor(dive, switches),
  );
}

/// A crude square profile for a chain dive that has no recorded samples:
/// descend, hold at max depth, ascend. Keeps the chain's loading continuous.
List<DiveProfilePoint> _squareProfile(Dive dive) {
  final maxDepth = dive.maxDepth ?? 0;
  final total = (dive.runtime ?? dive.bottomTime ?? const Duration(minutes: 30))
      .inSeconds;
  if (maxDepth <= 0 || total < 120) {
    return [
      const DiveProfilePoint(timestamp: 0, depth: 0),
      DiveProfilePoint(timestamp: total <= 0 ? 60 : total, depth: 0),
    ];
  }
  final descend = (total * 0.1).round();
  final ascend = (total * 0.15).round();
  return [
    const DiveProfilePoint(timestamp: 0, depth: 0),
    DiveProfilePoint(timestamp: descend, depth: maxDepth),
    DiveProfilePoint(timestamp: total - ascend, depth: maxDepth),
    DiveProfilePoint(timestamp: total, depth: 0),
  ];
}

List<GasLeg> _gasLegsFor(Dive dive, List<GasSwitchWithTank> switches) {
  final legs = <GasLeg>[];
  if (dive.tanks.isNotEmpty) {
    final primary = ([
      ...dive.tanks,
    ]..sort((a, b) => a.order.compareTo(b.order))).first;
    legs.add(
      GasLeg(
        startSeconds: 0,
        fN2: primary.gasMix.n2 / 100,
        fHe: primary.gasMix.he / 100,
      ),
    );
  } else {
    legs.add(const GasLeg(startSeconds: 0, fN2: airN2Fraction));
  }
  for (final sw in switches) {
    legs.add(
      GasLeg(
        startSeconds: sw.gasSwitch.timestamp,
        fN2: (1 - sw.o2Fraction - sw.heFraction).clamp(0.0, 1.0),
        fHe: sw.heFraction,
      ),
    );
  }
  legs.sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
  return legs;
}
