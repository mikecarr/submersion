import 'package:flutter/material.dart' show Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:submersion/features/divers/domain/entities/diver.dart';
import 'package:submersion/features/safety/domain/entities/emergency_info.dart';
import 'package:submersion/features/safety/presentation/pages/emergency_card_page.dart';
import 'package:submersion/features/safety/presentation/providers/emergency_providers.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';

import '../../../../helpers/l10n_test_helpers.dart';
import '../../../../helpers/mock_providers.dart';

void main() {
  const hotline = EmergencyRegion(
    id: 'des-australia',
    name: 'DES Australia (Divers Emergency Service)',
    phone: '1800-088-200',
    countries: ['AU'],
  );

  final chamber = EmergencyChamber(
    id: 'au-townsville',
    name: 'Townsville University Hospital Hyperbaric Unit',
    country: 'AU',
    city: 'Townsville, QLD',
    phone: '+61-7-4433-1111',
    lastVerified: DateTime.utc(2026, 7, 1),
    isBuiltIn: true,
  );

  final diver = Diver(
    id: 'diver-1',
    name: 'Test Diver',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    bloodType: 'O+',
    allergies: 'Penicillin',
    emergencyContact: const EmergencyContact(
      name: 'Pat Example',
      phone: '+61-400-000-000',
      relation: 'Partner',
    ),
    insurance: const DiverInsurance(
      provider: 'DAN World',
      policyNumber: 'P-12345',
    ),
  );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => MockSettingsNotifier()),
          emergencyCardDataProvider.overrideWith(
            (ref) async => EmergencyCardData(
              countryCode: 'AU',
              hotline: hotline,
              emsNumber: '000',
              diver: diver,
              chambers: [chamber],
            ),
          ),
        ],
        child: localizedMaterialApp(home: const EmergencyCardPage()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('renders hotline, EMS, diver data, and chambers', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pump(tester);

    expect(find.textContaining('DES Australia'), findsOneWidget);
    expect(find.textContaining('1800-088-200'), findsOneWidget);
    expect(find.textContaining('000'), findsWidgets);
    expect(find.text('Test Diver'), findsOneWidget);
    expect(find.textContaining('Blood type: O+'), findsOneWidget);
    expect(find.textContaining('Penicillin'), findsOneWidget);
    expect(find.textContaining('Pat Example'), findsOneWidget);
    expect(find.textContaining('DAN World'), findsOneWidget);
    expect(find.textContaining('Townsville'), findsWidgets);
    expect(find.textContaining('verified'), findsOneWidget);
  });
}
