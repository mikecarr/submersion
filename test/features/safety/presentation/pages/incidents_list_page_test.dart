import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:submersion/features/safety/domain/entities/incident.dart';
import 'package:submersion/features/safety/presentation/pages/incidents_list_page.dart';
import 'package:submersion/features/safety/presentation/providers/incident_providers.dart';

import '../../../../helpers/l10n_test_helpers.dart';

void main() {
  Incident incident({String? diveId}) => Incident(
    id: 'i1',
    occurredAt: DateTime.utc(2026, 7, 10),
    category: IncidentCategory.gasSupply,
    severity: IncidentSeverity.moderate,
    narrative: 'Free-flow at 18 m; switched to buddy octo.',
    createdAt: DateTime.utc(2026, 7, 10),
    updatedAt: DateTime.utc(2026, 7, 10),
    diveId: diveId,
  );

  Future<void> pump(WidgetTester tester, List<Incident> incidents) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [incidentsProvider.overrideWith((ref) async => incidents)],
        child: localizedMaterialApp(
          locale: const Locale('en'),
          home: const IncidentsListPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows the non-punitive empty state', (tester) async {
    await pump(tester, const []);
    expect(find.textContaining('without judgment'), findsOneWidget);
  });

  testWidgets('lists incidents with category and severity', (tester) async {
    await pump(tester, [incident(diveId: 'd1')]);
    expect(find.textContaining('Free-flow at 18 m'), findsOneWidget);
    expect(find.textContaining('Gas supply'), findsOneWidget);
    expect(find.textContaining('Moderate'), findsOneWidget);
    expect(find.textContaining('Linked to a dive'), findsOneWidget);
  });
}
