import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/deco/buhlmann_algorithm.dart';
import 'package:submersion/core/deco/entities/breathing_config.dart';
import 'package:submersion/core/deco/entities/profile_gas_segment.dart';

void main() {
  group('CCR tissue loading', () {
    test('CCR at setpoint loads less inert gas than OC diluent at 40 m', () {
      final oc = BuhlmannAlgorithm(gfLow: 0.5, gfHigh: 0.8);
      final ccr = BuhlmannAlgorithm(gfLow: 0.5, gfHigh: 0.8);

      oc.calculateSegment(
        depthMeters: 40,
        durationSeconds: 20 * 60,
        fN2: 0.37,
        fHe: 0.45,
      );
      ccr.calculateSegment(
        depthMeters: 40,
        durationSeconds: 20 * 60,
        breathing: const ClosedCircuit(
          setpoint: 1.3,
          diluentFO2: 0.18,
          diluentFHe: 0.45,
        ),
      );

      final ocInert = oc.compartments
          .map((c) => c.totalInertGas)
          .reduce((a, b) => a + b);
      final ccrInert = ccr.compartments
          .map((c) => c.totalInertGas)
          .reduce((a, b) => a + b);
      expect(ccrInert, lessThan(ocInert));
    });

    test('CCR NDL at setpoint is longer than OC NDL on the diluent', () {
      final algo = BuhlmannAlgorithm(gfLow: 0.5, gfHigh: 0.8);
      final ndlOc = algo.calculateNdl(depthMeters: 30, fN2: 0.7902, fHe: 0.0);
      final ndlCcr = algo.calculateNdl(
        depthMeters: 30,
        breathing: const ClosedCircuit(setpoint: 1.3, diluentFO2: 0.21),
      );
      expect(ndlCcr, greaterThan(ndlOc));
    });

    test('breathing parameter takes precedence over fN2/fHe', () {
      final a = BuhlmannAlgorithm();
      final b = BuhlmannAlgorithm();
      a.calculateSegment(
        depthMeters: 30,
        durationSeconds: 600,
        fN2: 0.5,
        fHe: 0.4,
        breathing: const OpenCircuit(fO2: 0.2098),
      );
      b.calculateSegment(
        depthMeters: 30,
        durationSeconds: 600,
        fN2: 0.7902,
        fHe: 0.0,
      );
      expect(a.compartments, b.compartments);
    });

    test('processProfileWithGasSegments honors segment setpoints', () {
      final depths = [0.0, 30.0, 30.0, 30.0, 0.0];
      final times = [0, 120, 600, 1200, 1500];

      final ocStatuses = BuhlmannAlgorithm(gfLow: 0.5, gfHigh: 0.8)
          .processProfileWithGasSegments(
            depths: depths,
            timestamps: times,
            gasSegments: [
              const ProfileGasSegment(startTimestamp: 0, fN2: 0.7902),
            ],
          );
      final ccrStatuses = BuhlmannAlgorithm(gfLow: 0.5, gfHigh: 0.8)
          .processProfileWithGasSegments(
            depths: depths,
            timestamps: times,
            gasSegments: [
              const ProfileGasSegment(
                startTimestamp: 0,
                fN2: 0.7902,
                setpoint: 1.3,
              ),
            ],
          );

      // At the last bottom sample the CCR diver has less N2 loaded.
      final ocN2 = ocStatuses[3].compartments.first.currentPN2;
      final ccrN2 = ccrStatuses[3].compartments.first.currentPN2;
      expect(ccrN2, lessThan(ocN2));
    });
  });
}
