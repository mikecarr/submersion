import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/settings/presentation/pages/troubleshoot_sync_page.dart';

void main() {
  testWidgets('shows Repair Sync action with an explanation', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: TroubleshootSyncPage())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Repair Sync'), findsOneWidget);
    // The explanation must reassure the user their dive data is safe.
    expect(find.textContaining('dive data'), findsWidgets);
  });
}
