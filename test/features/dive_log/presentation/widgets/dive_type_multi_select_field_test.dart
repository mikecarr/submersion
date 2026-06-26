import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_log/presentation/widgets/dive_type_multi_select_field.dart';
import 'package:submersion/features/dive_types/domain/entities/dive_type_entity.dart';
import 'package:submersion/features/dive_types/presentation/providers/dive_type_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

void main() {
  DiveTypeEntity type(String id, String name) => DiveTypeEntity(
    id: id,
    name: name,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  Widget harness({
    required List<String> selected,
    required ValueChanged<List<String>> onChanged,
    bool allowEmpty = false,
  }) {
    return ProviderScope(
      overrides: [
        diveTypesProvider.overrideWith(
          (ref) async => [
            type('shore', 'Shore'),
            type('wreck', 'Wreck'),
            type('night', 'Night'),
          ],
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DiveTypeMultiSelectField(
            selectedTypeIds: selected,
            onChanged: onChanged,
            allowEmpty: allowEmpty,
          ),
        ),
      ),
    );
  }

  testWidgets('renders a chip per selected type', (tester) async {
    await tester.pumpWidget(harness(selected: ['shore'], onChanged: (_) {}));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Chip, 'Shore'), findsOneWidget);
  });

  testWidgets(
    'tapping the field opens a checklist and toggling fires onChanged',
    (tester) async {
      List<String>? result;
      await tester.pumpWidget(
        harness(selected: ['shore'], onChanged: (v) => result = v),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(InkWell).first); // open the checklist
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNWidgets(3));

      await tester.tap(find.widgetWithText(CheckboxListTile, 'Wreck'));
      await tester.pumpAndSettle();

      expect(result, ['shore', 'wreck']);
    },
  );

  testWidgets('checklist stays open across multiple sequential toggles', (
    tester,
  ) async {
    final results = <List<String>>[];
    await tester.pumpWidget(
      harness(selected: ['shore'], onChanged: results.add),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Wreck'));
    await tester.pumpAndSettle();

    // The sheet stays open so a second type is reachable without reopening.
    expect(find.widgetWithText(CheckboxListTile, 'Night'), findsOneWidget);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Night'));
    await tester.pumpAndSettle();

    expect(results, [
      ['shore', 'wreck'],
      ['shore', 'wreck', 'night'],
    ]);
  });

  testWidgets('cannot uncheck the last remaining type (>= 1)', (tester) async {
    List<String>? result;
    await tester.pumpWidget(
      harness(selected: ['shore'], onChanged: (v) => result = v),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckboxListTile, 'Shore'),
    ); // try to uncheck the only type
    await tester.pumpAndSettle();

    expect(result, isNull); // the uncheck was ignored
  });

  testWidgets('allowEmpty lets the last type be unchecked (bulk mode)', (
    tester,
  ) async {
    List<String>? result;
    await tester.pumpWidget(
      harness(
        selected: ['shore'],
        onChanged: (v) => result = v,
        allowEmpty: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Shore'));
    await tester.pumpAndSettle();

    expect(result, isEmpty); // bulk mode allows clearing
  });
}
