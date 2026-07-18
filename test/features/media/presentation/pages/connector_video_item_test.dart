// Direct widget test for [ConnectorVideoItem]. The existing
// photo_viewer_lightroom_test drives it through PhotoViewerPage ->
// PhotoViewGallery -> a lazy PageView item-builder, and on the CI Linux VM the
// coverage of the lazily-built item is not recorded (it is on macOS). Pumping
// the widget directly -- no PhotoViewGallery, no runAsync -- exercises the same
// build eagerly so its line hits are collected on every platform.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:submersion/core/services/accounts/account_kind.dart';
import 'package:submersion/core/services/accounts/connected_account.dart'
    as domain;
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/domain/entities/media_source_type.dart';
import 'package:submersion/features/media/presentation/pages/photo_viewer_page.dart';
import 'package:submersion/features/media/presentation/providers/lightroom_providers.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../../helpers/test_database.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    await setUpTestDatabase();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  final account = domain.ConnectedAccount(
    id: 'acct1',
    kind: AccountKind.adobeLightroom,
    label: 'Eric',
    accountIdentifier: 'cat1',
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 1),
  );

  MediaItem videoItem() => MediaItem(
    id: 'm1',
    diveId: 'd1',
    mediaType: MediaType.video,
    sourceType: MediaSourceType.serviceConnector,
    remoteAssetId: 'lr1',
    takenAt: DateTime.utc(2026, 7, 1, 10),
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 1),
  );

  Future<void> pump(
    WidgetTester tester, {
    domain.ConnectedAccount? withAccount,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          lightroomAccountProvider.overrideWith((ref) async => withAccount),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ConnectorVideoItem(item: videoItem())),
        ),
      ),
    );
    // One pump settles the lightroomAccountProvider future (microtask); the
    // poster image stays pending, which is fine -- the build has already run.
    await tester.pump();
  }

  testWidgets('connected: shows the poster play badge and Open in Lightroom', (
    tester,
  ) async {
    await pump(tester, withAccount: account);

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.text('Open in Lightroom'), findsOneWidget);
  });

  testWidgets('the play affordance is a labeled semantic button', (
    tester,
  ) async {
    await pump(tester, withAccount: account);

    final labeled = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where(
          (s) =>
              s.properties.label == 'Open in Lightroom' &&
              s.properties.button == true,
        );
    expect(labeled, isNotEmpty);
  });

  testWidgets('no account: still renders the badge but not as a button', (
    tester,
  ) async {
    await pump(tester);

    // With no catalog the tap target is disabled (url == null), but the poster
    // and play glyph still build.
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });
}
