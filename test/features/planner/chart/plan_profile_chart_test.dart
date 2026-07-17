import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/core/constants/map_style.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_planner/presentation/providers/dive_planner_providers.dart';
import 'package:submersion/features/planner/presentation/chart/plan_chart_series_painter.dart';
import 'package:submersion/features/planner/presentation/chart/plan_profile_chart.dart';
import 'package:submersion/features/planner/presentation/providers/plan_canvas_providers.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';

import '../../../helpers/test_app.dart';

class _TestSettingsNotifier extends StateNotifier<AppSettings>
    implements SettingsNotifier {
  _TestSettingsNotifier() : super(const AppSettings());

  @override
  Future<void> setMapStyle(MapStyle style) async =>
      state = state.copyWith(mapStyle: style);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Widget harness() => testApp(
    overrides: [
      settingsProvider.overrideWith((ref) => _TestSettingsNotifier()),
    ],
    child: const SizedBox(width: 500, height: 400, child: PlanProfileChart()),
  );

  PlanChartSeriesPainter seriesPainter(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(find.byKey(const Key('planChartSeries')))
              .painter
          as PlanChartSeriesPainter;

  testWidgets('renders the empty state with a quick-plan action', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('planChartSeries')), findsNothing);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
  });

  testWidgets('empty-state action opens the quick-plan dialog', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.auto_awesome));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('renders all three paint layers once a plan exists', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlanProfileChart)),
    );
    container
        .read(divePlanNotifierProvider.notifier)
        .addSimplePlan(maxDepth: 30, bottomTimeMinutes: 20);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('planChartBackdrop')), findsOneWidget);
    expect(find.byKey(const Key('planChartSeries')), findsOneWidget);
    expect(find.byKey(const Key('planChartOverlay')), findsOneWidget);
  });

  testWidgets('gas switch reaches the painter and scrub shows the readout', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlanProfileChart)),
    );
    final notifier = container.read(divePlanNotifierProvider.notifier);
    notifier.addSimplePlan(maxDepth: 45, bottomTimeMinutes: 25);
    notifier.addTank(
      const DiveTank(
        id: 'o2',
        volume: 11.1,
        startPressure: 207,
        gasMix: GasMix(o2: 100),
        role: TankRole.deco,
      ),
    );
    await tester.pumpAndSettle();

    expect(seriesPainter(tester).series.gasSwitches, isNotEmpty);

    container.read(scrubTimeProvider.notifier).state = 300;
    await tester.pumpAndSettle();
    expect(find.textContaining('RT'), findsOneWidget);
  });

  testWidgets('dragging on the chart scrubs; releasing clears', (tester) async {
    await tester.pumpWidget(harness());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlanProfileChart)),
    );
    container
        .read(divePlanNotifierProvider.notifier)
        .addSimplePlan(maxDepth: 30, bottomTimeMinutes: 20);
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byKey(const Key('planChartOverlay')));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(container.read(scrubTimeProvider), isNotNull);

    await gesture.up();
    await tester.pump();
    expect(container.read(scrubTimeProvider), isNull);
  });

  testWidgets('tapping selects the segment under the pointer', (tester) async {
    await tester.pumpWidget(harness());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlanProfileChart)),
    );
    container
        .read(divePlanNotifierProvider.notifier)
        .addSimplePlan(maxDepth: 30, bottomTimeMinutes: 20);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('planChartOverlay')));
    await tester.pump();
    expect(container.read(selectedSegmentIdProvider), isNotNull);
  });

  testWidgets('mouse hover scrubs and exit clears', (tester) async {
    await tester.pumpWidget(harness());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlanProfileChart)),
    );
    container
        .read(divePlanNotifierProvider.notifier)
        .addSimplePlan(maxDepth: 30, bottomTimeMinutes: 20);
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getCenter(find.byKey(const Key('planChartOverlay'))),
    );
    await tester.pump();
    expect(container.read(scrubTimeProvider), isNotNull);

    // (700, 500) is inside the test window but outside the 500x400 chart;
    // Offset.zero would still be the chart's own top-left corner.
    await gesture.moveTo(const Offset(700, 500));
    await tester.pump();
    expect(container.read(scrubTimeProvider), isNull);
  });
}
