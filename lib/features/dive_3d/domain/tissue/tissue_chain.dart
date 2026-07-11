import 'package:submersion/core/deco/constants/buhlmann_coefficients.dart';
import 'package:submersion/core/deco/entities/dive_environment.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';

/// A derived repetitive-dive chain: the dives (earliest first) and the
/// surface interval (seconds) between each consecutive pair.
class TissueDiveChain {
  final List<Dive> dives;
  final List<int> surfaceIntervals;

  const TissueDiveChain({required this.dives, required this.surfaceIntervals});

  bool get hasMultipleDives => dives.length > 1;
}

/// A breathing gas active from [startSeconds] onward within one dive.
class GasLeg {
  final int startSeconds;
  final double fN2;
  final double fHe;

  const GasLeg({required this.startSeconds, required this.fN2, this.fHe = 0.0});

  static const GasLeg air = GasLeg(startSeconds: 0, fN2: airN2Fraction);
}

/// One dive's replay input: decimated time/depth series plus the gas legs
/// that were breathed. Times are seconds from that dive's descent.
class TissueDiveInput {
  final List<double> times;
  final List<double> depths;
  final List<GasLeg> gasLegs;

  const TissueDiveInput({
    required this.times,
    required this.depths,
    required this.gasLegs,
  });

  double get durationSeconds => times.isEmpty ? 0 : times.last;

  /// The gas active at [seconds] (last leg whose start is <= seconds).
  GasLeg gasAt(int seconds) {
    var chosen = gasLegs.isEmpty ? GasLeg.air : gasLegs.first;
    for (final leg in gasLegs) {
      if (leg.startSeconds <= seconds) {
        chosen = leg;
      } else {
        break;
      }
    }
    return chosen;
  }
}

/// A repetitive-dive chain: dives in time order with the surface interval
/// (seconds) between each consecutive pair. GF as fractions 0..1.
class TissueChainInput {
  final List<TissueDiveInput> dives;
  final List<int> surfaceIntervalSeconds; // length dives.length - 1
  final double gfLow;
  final double gfHigh;
  final DiveEnvironment environment;

  const TissueChainInput({
    required this.dives,
    required this.surfaceIntervalSeconds,
    required this.gfLow,
    required this.gfHigh,
    required this.environment,
  });
}
