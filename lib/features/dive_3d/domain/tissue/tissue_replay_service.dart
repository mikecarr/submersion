import 'dart:typed_data';

import 'package:submersion/core/deco/buhlmann_algorithm.dart';
import 'package:submersion/core/deco/constants/buhlmann_coefficients.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_chain.dart';
import 'package:submersion/features/dive_3d/domain/tissue/tissue_replay_result.dart';

/// Replays a repetitive-dive chain through the Buhlmann ZHL-16C engine,
/// snapshotting the 16-compartment inert-gas loading at every sample and at
/// several points across each surface interval. Pure and isolate-friendly:
/// the mutable engine is stepped with the exact `calculateSegment`
/// primitive the golden-vector corpus validates.
class TissueReplayService {
  static const int _surfaceChunks = 8;

  const TissueReplayService();

  TissueReplayResult replay(TissueChainInput chain) {
    const k = TissueReplayResult.compartmentCount;
    final algo = BuhlmannAlgorithm(
      gfLow: chain.gfLow,
      gfHigh: chain.gfHigh,
      environment: chain.environment,
    );

    final times = <double>[];
    final depths = <double>[];
    final isSurface = <bool>[];
    final n2 = <double>[];
    final he = <double>[];
    final gf = <double>[];
    final controlling = <int>[];
    final seamColumns = <int>[];
    var hasHelium = false;
    var maxLoading = 0.0;
    var clock = 0.0;

    void snapshot(double depth, {required bool surface}) {
      final ambient = chain.environment.pressureAtDepth(depth);
      final comps = algo.compartments;
      var bestGf = double.negativeInfinity;
      var bestIdx = 0;
      for (var c = 0; c < k; c++) {
        final comp = comps[c];
        final pN2 = comp.currentPN2;
        final pHe = comp.currentPHe;
        final grad = comp.gradientFactor(ambient);
        n2.add(pN2);
        he.add(pHe);
        gf.add(grad);
        if (pHe > 1e-6) hasHelium = true;
        final total = pN2 + pHe;
        if (total > maxLoading) maxLoading = total;
        if (grad > bestGf) {
          bestGf = grad;
          bestIdx = c;
        }
      }
      controlling.add(bestIdx);
      times.add(clock);
      depths.add(depth);
      isSurface.add(surface);
    }

    for (var d = 0; d < chain.dives.length; d++) {
      final dive = chain.dives[d];
      for (var i = 0; i < dive.times.length; i++) {
        if (i > 0) {
          final dt = (dive.times[i] - dive.times[i - 1]).round();
          if (dt > 0) {
            final avgDepth = (dive.depths[i - 1] + dive.depths[i]) / 2;
            final gas = dive.gasAt(dive.times[i - 1].round());
            algo.calculateSegment(
              depthMeters: avgDepth,
              durationSeconds: dt,
              fN2: gas.fN2,
              fHe: gas.fHe,
            );
          }
        }
        clock = _diveOffset(chain, d) + dive.times[i];
        snapshot(dive.depths[i], surface: false);
      }

      if (d < chain.surfaceIntervalSeconds.length) {
        final si = chain.surfaceIntervalSeconds[d];
        seamColumns.add(times.length);
        final chunk = (si / _surfaceChunks).ceil();
        var elapsed = 0;
        final base = _diveOffset(chain, d) + dive.durationSeconds;
        while (elapsed < si) {
          final step = elapsed + chunk > si ? si - elapsed : chunk;
          algo.calculateSegment(
            depthMeters: 0,
            durationSeconds: step,
            fN2: airN2Fraction,
          );
          elapsed += step;
          clock = base + elapsed;
          snapshot(0, surface: true);
        }
      }
    }

    return TissueReplayResult(
      times: times,
      depths: depths,
      isSurface: isSurface,
      loadingsN2: Float32List.fromList(n2),
      loadingsHe: Float32List.fromList(he),
      gradientFactors: Float32List.fromList(gf),
      controlling: Uint8List.fromList(controlling),
      seamColumns: seamColumns,
      hasHelium: hasHelium,
      maxLoadingBar: maxLoading,
      totalClockSeconds: times.isEmpty ? 0 : times.last,
      diveDurations: [for (final d in chain.dives) d.durationSeconds.round()],
      surfaceIntervals: List<int>.from(chain.surfaceIntervalSeconds),
    );
  }

  /// Chain-clock offset (seconds) at the start of dive [index].
  double _diveOffset(TissueChainInput chain, int index) {
    var offset = 0.0;
    for (var d = 0; d < index; d++) {
      offset += chain.dives[d].durationSeconds;
      if (d < chain.surfaceIntervalSeconds.length) {
        offset += chain.surfaceIntervalSeconds[d];
      }
    }
    return offset;
  }
}
