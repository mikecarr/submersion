import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/map_style.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_planner/presentation/providers/dive_planner_providers.dart';
import 'package:submersion/features/dive_planner/presentation/widgets/setup/plan_rates_section.dart';
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
  testWidgets('shows ascent and descent sliders reflecting plan state', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        overrides: [
          settingsProvider.overrideWith((ref) => _TestSettingsNotifier()),
        ],
        child: const SingleChildScrollView(child: PlanRatesSection()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsNWidgets(2));
    expect(find.text('9 m/min'), findsOneWidget); // default ascent
    expect(find.text('18 m/min'), findsOneWidget); // default descent

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlanRatesSection)),
    );
    final ascent = tester.widgetList<Slider>(find.byType(Slider)).first;
    ascent.onChanged!(6);
    await tester.pumpAndSettle();
    expect(container.read(divePlanNotifierProvider).ascentRate, 6);
  });
}
