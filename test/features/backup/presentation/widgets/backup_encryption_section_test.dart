import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';
import 'package:submersion/features/backup/presentation/widgets/backup_encryption_section.dart';

Future<void> _pump(WidgetTester tester, {required bool enabled}) async {
  SharedPreferences.setMockInitialValues(
    enabled ? {'backup_encryption_enabled': true} : {},
  );
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: BackupEncryptionSection()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('off state offers to encrypt backups', (tester) async {
    await _pump(tester, enabled: false);
    expect(find.text('Encrypt backups'), findsOneWidget);
    expect(find.text('Change password'), findsNothing);
  });

  testWidgets('on state shows manage actions', (tester) async {
    await _pump(tester, enabled: true);
    expect(find.text('Change password'), findsOneWidget);
    expect(find.text('Regenerate recovery code'), findsOneWidget);
    expect(find.text('Turn off encryption'), findsOneWidget);
    expect(find.text('Encrypt backups'), findsNothing);
  });

  testWidgets('tapping Encrypt backups opens the enable dialog', (
    tester,
  ) async {
    await _pump(tester, enabled: false);
    await tester.tap(find.text('Encrypt backups'));
    await tester.pumpAndSettle();
    // The enable dialog's two password fields are shown; no crypto runs yet.
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Continue'), findsOneWidget);
  });
}
