import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/features/certifications/data/repositories/certification_repository.dart';
import 'package:submersion/features/certifications/domain/entities/certification.dart';
import 'package:submersion/features/certifications/presentation/pages/certification_edit_page.dart';
import 'package:submersion/features/certifications/presentation/providers/certification_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/test_database.dart';

void main() {
  late CertificationRepository repository;

  setUp(() async {
    await setUpTestDatabase();
    repository = CertificationRepository();
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  testWidgets('staging mode returns a Certification via onStaged without '
      'persisting', (tester) async {
    Certification? staged;
    final overrides = await getBaseOverrides();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides,
          certificationRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: CertificationEditPage(
              embedded: true,
              initialCertification: Certification(
                id: 'staged-1',
                buddyId: 'b1',
                name: 'Nitrox',
                agency: CertificationAgency.padi,
                createdAt: DateTime(2024),
                updatedAt: DateTime(2024),
              ),
              onStaged: (c) => staged = c,
              onSaved: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(staged, isNotNull);
    expect(staged!.id, 'staged-1');
    expect(staged!.buddyId, 'b1');
    expect(staged!.name, 'Nitrox');

    // Staging bypasses the repository: nothing was persisted.
    expect(await repository.getCertificationById('staged-1'), isNull);
  });
}
