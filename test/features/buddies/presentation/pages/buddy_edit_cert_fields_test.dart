import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/buddies/data/repositories/buddy_repository.dart';
import 'package:submersion/features/buddies/domain/entities/buddy.dart';
import 'package:submersion/features/buddies/presentation/pages/buddy_edit_page.dart';
import 'package:submersion/features/certifications/data/repositories/certification_repository.dart';
import 'package:submersion/features/certifications/domain/entities/certification.dart';
import 'package:submersion/features/divers/data/repositories/diver_repository.dart';
import 'package:submersion/features/divers/domain/entities/diver.dart';
import 'package:submersion/features/divers/presentation/providers/diver_providers.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/test_database.dart';

// Issue #553: the buddy edit page's two cert dropdowns were replaced with a
// staged "Certifications" section (a list + Add-certification dialog). These
// tests cover the new section; buddy certs now live in the certifications
// table, not on the buddy row.
void main() {
  late BuddyRepository buddyRepo;
  late CertificationRepository certRepo;
  late SharedPreferences prefs;

  setUp(() async {
    await setUpTestDatabase();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    buddyRepo = BuddyRepository();
    certRepo = CertificationRepository();

    final diver = await DiverRepository().createDiver(
      Diver(
        id: '',
        name: 'D',
        isDefault: true,
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      ),
    );
    await prefs.setString(currentDiverIdKey, diver.id);
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  Widget harness({String? buddyId, List<Buddy>? mergeBuddies}) {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        settingsProvider.overrideWith((ref) => MockSettingsNotifier()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: BuddyEditPage(
            buddyId: buddyId,
            mergeBuddies: mergeBuddies,
            embedded: true,
          ),
        ),
      ),
    );
  }

  testWidgets('shows the Certifications section with existing certs and an '
      'Add button', (tester) async {
    final now = DateTime(2024);
    final buddy = await buddyRepo.createBuddy(
      Buddy(id: '', name: 'Sarah', createdAt: now, updatedAt: now),
    );
    await certRepo.createCertification(
      Certification(
        id: '',
        buddyId: buddy.id,
        name: 'Nitrox',
        agency: CertificationAgency.padi,
        level: CertificationLevel.nitrox,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(harness(buddyId: buddy.id));
    await tester.pumpAndSettle();

    expect(find.text('Certifications'), findsOneWidget);
    expect(find.text('Nitrox'), findsOneWidget); // cert row title
    expect(find.text('Add certification'), findsOneWidget);
    // The old inline dropdowns are gone.
    expect(
      find.byType(DropdownButtonFormField<CertificationAgency>),
      findsNothing,
    );
  });

  testWidgets('new buddy shows an empty Certifications section with an Add '
      'button', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Certifications'), findsOneWidget);
    expect(find.text('Add certification'), findsOneWidget);
  });

  testWidgets('merge mode hides the Certifications section (survivor inherits '
      'the union at the repository level)', (tester) async {
    final now = DateTime(2024);
    final survivor = Buddy(
      id: 'b1',
      name: 'Alice',
      createdAt: now,
      updatedAt: now,
    );
    final duplicate = Buddy(
      id: 'b2',
      name: 'Alice',
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(harness(mergeBuddies: [survivor, duplicate]));
    await tester.pumpAndSettle();

    expect(find.text('Add certification'), findsNothing);
    expect(find.text('Certifications'), findsNothing);
  });
}
