import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/services/database_service.dart';
import 'package:submersion/features/divers/data/repositories/diver_weight_entry_repository.dart';
import 'package:submersion/features/divers/domain/entities/diver_weight_entry.dart';
import 'package:submersion/features/divers/presentation/providers/diver_providers.dart';
import 'package:submersion/features/settings/presentation/pages/body_weight_edit_page.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/test_app.dart';
import '../../../../helpers/test_database.dart';

void main() {
  const diverId = 'test-diver-id';

  setUp(() async {
    await setUpTestDatabase();
    final db = DatabaseService.instance.database;
    await db.customStatement(
      "INSERT INTO divers (id, name, created_at, updated_at) "
      "VALUES ('$diverId', 'Eric', 1000, 1000)",
    );
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    final base = await getBaseOverrides();
    await tester.pumpWidget(
      testApp(
        overrides: [
          ...base,
          validatedCurrentDiverIdProvider.overrideWith((ref) async => diverId),
        ],
        child: const BodyWeightEditPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('adds a measurement through the dialog', (tester) async {
    await pumpPage(tester);
    expect(find.text('Not recorded'), findsOneWidget);

    await tester.tap(find.text('Add measurement'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Weight (kg)'),
      '82.5',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('82.5 kg'), findsOneWidget);
    final entries = await DiverWeightEntryRepository().getEntriesForDiver(
      diverId,
    );
    expect(entries.single.weightKg, 82.5);
  });

  testWidgets('deletes a measurement from the list', (tester) async {
    final repository = DiverWeightEntryRepository();
    final now = DateTime(2026, 6, 1);
    await repository.createEntry(
      DiverWeightEntry(
        id: '',
        diverId: diverId,
        measuredAt: now,
        weightKg: 80.0,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await pumpPage(tester);
    expect(find.text('80.0 kg'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete entry'));
    await tester.pumpAndSettle();

    expect(find.text('Not recorded'), findsOneWidget);
    expect(await repository.getEntriesForDiver(diverId), isEmpty);
  });
}
