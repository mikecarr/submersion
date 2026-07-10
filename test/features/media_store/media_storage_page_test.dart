import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:submersion/core/services/cloud_storage/s3/s3_config.dart';
import 'package:submersion/core/services/media_store/media_store_attach_state.dart';
import 'package:submersion/core/services/media_store/media_store_credentials_store.dart';
import 'package:submersion/features/media_store/data/media_store_service.dart';
import 'package:submersion/features/media_store/data/media_stores_repository.dart';
import 'package:submersion/features/media_store/presentation/pages/media_storage_page.dart';
import 'package:submersion/features/media_store/presentation/providers/media_store_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../helpers/in_memory_media_object_store.dart';
import '../../support/fake_keychain_storage.dart';

class _RecordingService extends MediaStoreService {
  _RecordingService()
    : super(
        credentials: MediaStoreCredentialsStore(storage: InMemoryKeychain()),
        attachState: MediaStoreAttachState(),
        storesRepository: MediaStoresRepository(),
        storeFactory: (_) => InMemoryMediaObjectStore(),
      );

  int connectCalls = 0;
  int testCalls = 0;

  @override
  Future<MediaStoreConnectResult> connectS3(S3Config config) async {
    connectCalls++;
    return const MediaStoreConnectResult(
      storeId: 'store-x',
      createdNewStore: true,
    );
  }

  @override
  Future<void> testConnection(S3Config config) async {
    testCalls++;
  }
}

void main() {
  late _RecordingService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = _RecordingService();
  });

  Widget app() => ProviderScope(
    overrides: [
      mediaStoreRuntimeProvider.overrideWith((ref) async => null),
      mediaStoreCredentialsStoreProvider.overrideWithValue(
        MediaStoreCredentialsStore(storage: InMemoryKeychain()),
      ),
      mediaStoreServiceProvider.overrideWithValue(service),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaStoragePage(),
    ),
  );

  testWidgets('shows the not-configured status and no disconnect '
      'button', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(app());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });

    expect(
      find.text('No media store connected on this device'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('media-s3-connect')), findsOneWidget);
    expect(find.byKey(const Key('media-s3-disconnect')), findsNothing);
  });

  testWidgets('invalid form blocks connect and never calls the '
      'service', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(app());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });

    await tester.ensureVisible(find.byKey(const Key('media-s3-connect')));
    await tester.tap(find.byKey(const Key('media-s3-connect')));
    await tester.pump();

    expect(service.connectCalls, 0);
    expect(find.byType(MediaStoragePage), findsOneWidget);
  });

  testWidgets('valid form calls connectS3 once', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(app());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });

    await tester.enterText(
      find.byKey(const Key('media-s3-endpoint')),
      'https://minio.example.com',
    );
    await tester.enterText(
      find.byKey(const Key('media-s3-bucket')),
      'dive-media',
    );
    await tester.enterText(find.byKey(const Key('media-s3-access-key')), 'AK');
    await tester.enterText(find.byKey(const Key('media-s3-secret-key')), 'SK');

    await tester.ensureVisible(find.byKey(const Key('media-s3-connect')));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('media-s3-connect')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });

    expect(service.connectCalls, 1);
  });
}
