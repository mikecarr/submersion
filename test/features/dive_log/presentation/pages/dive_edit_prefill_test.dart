import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_log/data/repositories/dive_repository_impl.dart';
import 'package:submersion/features/dive_log/domain/entities/dive_prefill.dart';
import 'package:submersion/features/dive_log/presentation/pages/dive_edit_page.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_providers.dart';
import 'package:submersion/features/tank_presets/presentation/providers/tank_preset_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/test_database.dart';

void main() {
  group('DiveEditPage prefill', () {
    late DiveRepository repository;

    setUp(() async {
      await setUpTestDatabase();
      repository = DiveRepository();
    });

    tearDown(() async {
      await tearDownTestDatabase();
    });

    Future<void> pumpEditPage(
      WidgetTester tester, {
      DivePrefill? prefill,
    }) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final overrides = await getBaseOverrides();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overrides,
            diveRepositoryProvider.overrideWithValue(repository),
            diveListNotifierProvider.overrideWith((ref) {
              return DiveListNotifier(repository, ref);
            }),
            customTankPresetsProvider.overrideWith((ref) async => []),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: DiveEditPage(embedded: true, prefill: prefill),
            ),
          ),
        ),
      );
      // No pumpAndSettle: the new-dive path starts a 10s GPS capture
      // whose pending timer never settles in tests.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('prefill populates create-mode fields', (tester) async {
      final prefill = DivePrefill(
        diveNumber: 66,
        dateTime: DateTime(2006, 2, 6, 10, 0),
        hasTimeOfDay: true,
        durationMinutes: 32,
        maxDepthMeters: 21.0,
        waterTempCelsius: 22.8,
        notes: 'WE SAW A HUMPBACK WHALE',
        rating: 5,
        startPressureBar: 206.8,
        endPressureBar: 110.3,
        importSource: 'ocr',
      );
      await pumpEditPage(tester, prefill: prefill);
      // The form renders values as FormRow text ('45 min' style), so match
      // by content rather than widget type.
      expect(find.textContaining('66'), findsWidgets);
      expect(find.textContaining('32 min'), findsWidgets);
      expect(find.text('WE SAW A HUMPBACK WHALE'), findsOneWidget);
      // Depth shown in the active display unit (metric default in tests).
      expect(find.textContaining('21.0'), findsWidgets);
    });

    testWidgets('no prefill leaves create mode unchanged', (tester) async {
      await pumpEditPage(tester);
      expect(find.text('WE SAW A HUMPBACK WHALE'), findsNothing);
      expect(find.byType(DiveEditPage), findsOneWidget);
    });
  });
}
