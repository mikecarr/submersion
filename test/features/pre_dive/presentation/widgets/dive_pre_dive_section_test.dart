import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/pre_dive/domain/entities/pre_dive_session.dart';
import 'package:submersion/features/pre_dive/presentation/providers/pre_dive_providers.dart';
import 'package:submersion/features/pre_dive/presentation/widgets/dive_pre_dive_section.dart';

import '../../../../helpers/test_app.dart';

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  Dive dive({bool planned = false}) =>
      Dive(id: 'd1', dateTime: now, isPlanned: planned);

  final linkedSession = PreDiveSession(
    id: 's1',
    templateName: 'BWRAF Buddy Check',
    diveId: 'd1',
    startedAt: now,
    completedAt: now,
    status: PreDiveSessionStatus.completed,
    createdAt: now,
    updatedAt: now,
  );

  Future<void> pumpSection(
    WidgetTester tester, {
    required Dive d,
    PreDiveSession? session,
  }) async {
    await tester.pumpWidget(
      testApp(
        overrides: [
          preDiveSessionForDiveProvider(
            'd1',
          ).overrideWith((ref) async => session),
          preDiveSessionItemsProvider(
            's1',
          ).overrideWith((ref) async => <PreDiveSessionItem>[]),
        ],
        child: DivePreDiveSection(dive: d),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('linked dive shows the session with Unlink menu', (tester) async {
    await pumpSection(tester, d: dive(), session: linkedSession);
    expect(find.text('BWRAF Buddy Check'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Unlink'), findsOneWidget);
  });

  testWidgets('unlinked planned dive offers Run', (tester) async {
    await pumpSection(tester, d: dive(planned: true));
    expect(find.text('Run pre-dive checklist'), findsOneWidget);
    expect(find.text('Link a checklist session'), findsNothing);
  });

  testWidgets('unlinked logged dive offers Link', (tester) async {
    await pumpSection(tester, d: dive());
    expect(find.text('Link a checklist session'), findsOneWidget);
    expect(find.text('Run pre-dive checklist'), findsNothing);
  });
}
