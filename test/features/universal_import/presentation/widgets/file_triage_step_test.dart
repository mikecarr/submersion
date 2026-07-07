import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/universal_import/data/models/detection_result.dart';
import 'package:submersion/features/universal_import/data/models/import_enums.dart';
import 'package:submersion/features/universal_import/data/models/picked_import_file.dart';
import 'package:submersion/features/universal_import/presentation/providers/universal_import_providers.dart';
import 'package:submersion/features/universal_import/presentation/widgets/file_triage_step.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

PickedImportFile file(
  String name,
  ImportFormat format,
  ImportFileStatus status,
) {
  return PickedImportFile(
    name: name,
    path: '/tmp/$name',
    detection: DetectionResult(format: format, confidence: 1),
    status: status,
  );
}

void main() {
  testWidgets('lists files with format names and greys excluded ones', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(universalImportNotifierProvider.notifier)
        .debugSetFilesForTest([
          file('a.fit', ImportFormat.fit, ImportFileStatus.pending),
          file('b.csv', ImportFormat.csv, ImportFileStatus.excludedCsv),
          file('c.xyz', ImportFormat.unknown, ImportFileStatus.unsupported),
        ]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: FileTriageStep()),
        ),
      ),
    );

    expect(find.text('a.fit'), findsOneWidget);
    expect(find.text('Garmin FIT'), findsOneWidget);
    expect(find.text('Import individually (CSV)'), findsOneWidget);
    expect(find.text('Unsupported format'), findsOneWidget);
    expect(find.text('1 file ready to import'), findsOneWidget);
  });
}
