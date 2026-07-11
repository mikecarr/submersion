import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_3d/application/providers.dart';
import 'package:submersion/features/dive_3d/domain/entities/dive_3d_scene_data.dart';
import 'package:submersion/features/dive_3d/presentation/widgets/dive_3d_preview_card.dart';

import '../../../../helpers/test_app.dart';

Dive3dSceneData fakeSceneData() => const Dive3dSceneData(
  diveId: 'd1',
  times: [0, 60, 120],
  depths: [0, 18, 0],
  temperatures: [20, 15, 20],
  ascentRates: [null, null, null],
  ppO2s: [null, null, null],
  cnss: [null, null, null],
  heartRates: [null, null, null],
  ceilings: [null, null, null],
  ttss: [null, null, null],
  tankPressures: {},
  gasSwitches: [],
  bookmarkEvents: [],
  photos: [],
  durationSeconds: 120,
  maxDepthMeters: 18,
);

void main() {
  testWidgets('renders nothing when the dive has no profile', (tester) async {
    await tester.pumpWidget(
      testApp(
        overrides: [
          dive3dSceneDataProvider('d1').overrideWith((ref) async => null),
        ],
        child: const Dive3dPreviewCard(diveId: 'd1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('renders the preview card when geometry is available', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        overrides: [
          dive3dSceneDataProvider(
            'd1',
          ).overrideWith((ref) async => fakeSceneData()),
        ],
        child: const Dive3dPreviewCard(diveId: 'd1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsOneWidget);
    expect(find.text('3D View'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
