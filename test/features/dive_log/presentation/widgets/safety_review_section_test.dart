import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:submersion/features/dive_log/domain/entities/safety_finding.dart';
import 'package:submersion/features/dive_log/presentation/providers/safety_review_providers.dart';
import 'package:submersion/features/dive_log/presentation/widgets/safety_review_section.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';

import '../../../../helpers/l10n_test_helpers.dart';
import '../../../../helpers/mock_providers.dart';

void main() {
  final now = DateTime.utc(2026, 7, 16);

  SafetyReview reviewWith(List<SafetyFinding> findings) => SafetyReview(
    diveId: 'dive-1',
    engineVersion: 1,
    reviewedAt: now,
    findings: findings,
  );

  SafetyFinding rapidAscent({DateTime? dismissedAt}) => SafetyFinding(
    id: 'f1',
    diveId: 'dive-1',
    ruleId: SafetyRuleId.rapidAscent,
    severity: SafetySeverity.significant,
    startTimestamp: 1500,
    endTimestamp: 1540,
    value: 14.2,
    engineVersion: 1,
    dismissedAt: dismissedAt,
    createdAt: now,
  );

  Future<void> pump(WidgetTester tester, SafetyReview review) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => MockSettingsNotifier()),
          safetyReviewProvider('dive-1').overrideWith((ref) async => review),
        ],
        child: localizedMaterialApp(
          home: const Scaffold(
            body: SingleChildScrollView(
              child: SafetyReviewSection(diveId: 'dive-1'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders a rapid ascent finding', (tester) async {
    await pump(tester, reviewWith([rapidAscent()]));
    expect(find.textContaining('Ascent exceeded'), findsOneWidget);
  });

  testWidgets('renders nothing when there are no findings', (tester) async {
    await pump(tester, reviewWith(const []));
    expect(find.text('Safety review'), findsNothing);
  });

  testWidgets('dismissed findings are hidden behind a toggle', (tester) async {
    await pump(tester, reviewWith([rapidAscent(dismissedAt: now)]));
    expect(find.textContaining('Ascent exceeded'), findsNothing);
    expect(find.textContaining('dismissed'), findsOneWidget);
  });
}
