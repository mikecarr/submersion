import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/divers/data/repositories/diver_repository.dart';
import 'package:submersion/features/divers/domain/entities/diver.dart';
import 'package:submersion/features/divers/presentation/pages/diver_edit_page.dart';
import 'package:submersion/features/divers/presentation/providers/diver_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../../helpers/mock_providers.dart';

class _CapturingNotifier extends StateNotifier<AsyncValue<List<Diver>>>
    implements DiverListNotifier {
  _CapturingNotifier() : super(const AsyncValue.data([]));
  Diver? added;

  @override
  Future<Diver> addDiver(Diver diver) async {
    added = diver;
    return diver.copyWith(id: 'new-id');
  }

  @override
  Future<void> updateDiver(Diver diver) async {}
  @override
  Future<void> refresh() async {}
  @override
  Future<DeleteDiverResult> deleteDiver(String id) async =>
      const DeleteDiverResult(reassignedTripsCount: 0, reassignedSitesCount: 0);
  @override
  Future<void> setAsDefault(String id) async {}
}

void main() {
  testWidgets('entering prior experience saves it onto the new Diver', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final notifier = _CapturingNotifier();
    final overrides = await getBaseOverrides();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides,
          diverListNotifierProvider.overrideWith((ref) => notifier),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: DiverEditPage(embedded: true, onSaved: (_) {})),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Test Diver');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Prior dives'),
      '1200',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Prior hours'),
      '1150',
    );
    await tester.pumpAndSettle();

    final addBtn = find.widgetWithText(FilledButton, 'Add Diver');
    await tester.ensureVisible(addBtn);
    await tester.pumpAndSettle();
    await tester.tap(addBtn);
    await tester.pumpAndSettle();

    expect(notifier.added, isNotNull);
    expect(notifier.added!.priorDiveCount, 1200);
    expect(notifier.added!.priorDiveTimeSeconds, 1150 * 3600);
  });
}
