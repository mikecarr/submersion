import 'dart:math' as math;

import 'package:submersion/core/deco/constants/buhlmann_coefficients.dart';
import 'package:submersion/core/deco/scr_calculator.dart';

/// Partial pressures of the inspired gas at some ambient pressure.
class InspiredGas {
  const InspiredGas({required this.pN2, required this.pHe, required this.pO2});

  final double pN2;
  final double pHe;
  final double pO2;
}

/// What the diver is breathing, independent of depth.
///
/// The engine asks a BreathingConfig for inspired partial pressures at an
/// ambient pressure; open circuit, constant-ppO2 CCR, and steady-state SCR
/// answer differently. All account for alveolar water vapor.
sealed class BreathingConfig {
  const BreathingConfig();

  /// Inspired partial pressures at [ambientPressureBar].
  InspiredGas inspiredAt(double ambientPressureBar);
}

/// Open circuit: fixed gas fractions at ambient pressure.
class OpenCircuit extends BreathingConfig {
  const OpenCircuit({required this.fO2, this.fHe = 0.0});

  final double fO2;
  final double fHe;

  double get fN2 => 1.0 - fO2 - fHe;

  @override
  InspiredGas inspiredAt(double ambientPressureBar) {
    final pAlv = math.max(ambientPressureBar - waterVaporPressure, 0.0);
    return InspiredGas(pN2: pAlv * fN2, pHe: pAlv * fHe, pO2: pAlv * fO2);
  }
}

/// Closed-circuit rebreather at a constant ppO2 setpoint.
///
/// Inspired inert pressure is what remains of the alveolar pressure after
/// the setpoint's O2, split by the diluent's N2:He ratio. Shallower than
/// the setpoint the loop is effectively pure O2 (the O2 pressure is capped
/// by the available alveolar pressure).
class ClosedCircuit extends BreathingConfig {
  const ClosedCircuit({
    required this.setpoint,
    required this.diluentFO2,
    this.diluentFHe = 0.0,
  });

  final double setpoint;
  final double diluentFO2;
  final double diluentFHe;

  double get diluentFN2 => 1.0 - diluentFO2 - diluentFHe;

  @override
  InspiredGas inspiredAt(double ambientPressureBar) {
    final pAlv = math.max(ambientPressureBar - waterVaporPressure, 0.0);
    final pO2 = math.min(setpoint, pAlv);
    final pInert = math.max(pAlv - pO2, 0.0);
    final inertFraction = diluentFN2 + diluentFHe;
    if (inertFraction <= 0) {
      return InspiredGas(pN2: 0, pHe: 0, pO2: pAlv);
    }
    final n2Share = diluentFN2 / inertFraction;
    return InspiredGas(
      pN2: pInert * n2Share,
      pHe: pInert * (1.0 - n2Share),
      pO2: pO2,
    );
  }
}

/// CMF semi-closed rebreather at steady state.
///
/// The loop behaves like open circuit on the steady-state loop mix derived
/// from the supply gas via [ScrCalculator.calculateCmfSteadyStateFo2]. The
/// supply's He:N2 ratio is preserved in the loop (metabolism only removes
/// O2). If the flow is insufficient (hypoxic), the supply mix is used and
/// callers surface that as a warning.
class Scr extends BreathingConfig {
  Scr({
    required this.supplyFO2,
    this.supplyFHe = 0.0,
    required this.injectionRateLpm,
    this.vo2 = ScrCalculator.defaultVo2,
  }) : _loop = _steadyStateLoop(supplyFO2, supplyFHe, injectionRateLpm, vo2);

  final double supplyFO2;
  final double supplyFHe;
  final double injectionRateLpm;
  final double vo2;
  final OpenCircuit _loop;

  static OpenCircuit _steadyStateLoop(
    double supplyFO2,
    double supplyFHe,
    double injectionRateLpm,
    double vo2,
  ) {
    final loopFO2 =
        ScrCalculator.calculateCmfSteadyStateFo2(
          injectionRateLpm: injectionRateLpm,
          supplyO2Percent: supplyFO2 * 100.0,
          vo2: vo2,
        ) ??
        supplyFO2;
    final supplyInert = 1.0 - supplyFO2;
    final heShare = supplyInert > 0 ? supplyFHe / supplyInert : 0.0;
    final loopInert = 1.0 - loopFO2;
    return OpenCircuit(fO2: loopFO2, fHe: loopInert * heShare);
  }

  @override
  InspiredGas inspiredAt(double ambientPressureBar) =>
      _loop.inspiredAt(ambientPressureBar);
}
