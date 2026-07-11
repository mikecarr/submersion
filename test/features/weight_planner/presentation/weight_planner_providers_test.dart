import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/buoyancy/weight_observation.dart';
import 'package:submersion/core/buoyancy/weight_prediction_engine.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_planner/presentation/providers/dive_planner_providers.dart';
import 'package:submersion/features/divers/domain/entities/diver_weight_entry.dart';
import 'package:submersion/features/divers/presentation/providers/diver_weight_entry_providers.dart';
import 'package:submersion/features/equipment/domain/entities/equipment_item.dart';
import 'package:submersion/features/equipment/presentation/providers/equipment_providers.dart';
import 'package:submersion/features/weight_planner/presentation/providers/weight_planner_providers.dart';

import '../../../helpers/mock_providers.dart';

void main() {
  const suitItem = EquipmentItem(
    id: 'suit',
    name: '5mm Suit',
    type: EquipmentType.wetsuit,
  );
  const leadItem = EquipmentItem(
    id: 'lead',
    name: 'Trim pockets',
    type: EquipmentType.weights,
  );

  final entry = DiverWeightEntry(
    id: 'w1',
    diverId: 'diver-1',
    measuredAt: DateTime(2026, 6, 1),
    weightKg: 80,
    createdAt: DateTime(2026, 6, 1),
    updatedAt: DateTime(2026, 6, 1),
  );

  List<WeightObservation> observations() => [
    for (var i = 0; i < 12; i++)
      WeightObservation(
        diveId: 'd$i',
        diveDateTime: DateTime(2026, 6, 1).subtract(Duration(days: i)),
        waterType: WaterType.salt,
        carriedKg: 8.0,
        equipmentIds: const ['suit'],
        tanks: const [
          ObservedTank(
            presetName: 'al80',
            volumeL: 11.1,
            workingPressureBar: 207,
            material: TankMaterial.aluminum,
          ),
        ],
        feedback: 'correct',
      ),
  ];

  Future<ProviderContainer> container() async {
    final base = await getBaseOverrides();
    final c = ProviderContainer(
      overrides: [
        ...base,
        weightObservationsProvider.overrideWith((ref) async => observations()),
        allEquipmentProvider.overrideWith(
          (ref) async => const [suitItem, leadItem],
        ),
        latestDiverWeightProvider.overrideWith((ref) async => entry),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('gearFeatureFor excludes weights and tank types', () {
    expect(gearFeatureFor(leadItem), isNull);
    expect(
      gearFeatureFor(
        const EquipmentItem(id: 't', name: 'AL80', type: EquipmentType.tank),
      ),
      isNull,
    );
    final suit = gearFeatureFor(suitItem);
    expect(suit!.priorKg, closeTo(5.0, 0.001));
  });

  test('gearFeatureFor passes user metadata through', () {
    final feature = gearFeatureFor(
      suitItem.copyWith(buoyancyKg: -2.0, weightKg: 2.5),
    );
    expect(feature!.priorKg, -2.0);
    expect(feature.hasUserSpec, isTrue);
    expect(feature.dryMassKg, 2.5);
  });

  test('weightCalibrationProvider fits a usable model', () async {
    final c = await container();
    final model = await c.read(weightCalibrationProvider.future);
    expect(model.supportingDives, 12);
    final prediction = model.predict(
      RigSpec(
        gear: [gearFeatureFor(suitItem)!],
        tanks: const [
          TankSpec(
            presetName: 'al80',
            volumeL: 11.1,
            workingPressureBar: 207,
            material: TankMaterial.aluminum,
          ),
        ],
        waterType: WaterType.salt,
        bodyWeightKg: 80,
      ),
    );
    expect(prediction.totalKg, closeTo(8.0, 0.6));
  });

  test('planWeightPredictionProvider is null while loading, then predicts '
      'from the plan state', () async {
    final c = await container();
    expect(c.read(planWeightPredictionProvider), isNull);

    await c.read(weightCalibrationProvider.future);
    await c.read(allEquipmentProvider.future);
    await c.read(latestDiverWeightProvider.future);

    final notifier = c.read(divePlanNotifierProvider.notifier);
    notifier.addTank(
      const DiveTank(
        id: 't1',
        volume: 11.1,
        workingPressure: 207,
        material: TankMaterial.aluminum,
        presetName: 'al80',
      ),
    );
    notifier.setEquipmentIds(['suit', 'lead']);

    final prediction = c.read(planWeightPredictionProvider);
    expect(prediction, isNotNull);
    // The excluded lead item contributes nothing; suit + tank dominate.
    expect(prediction!.totalKg, greaterThan(4.0));
    expect(prediction.supportingDives, 12);
  });
}
