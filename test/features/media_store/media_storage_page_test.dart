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
import 'package:submersion/features/settings/presentation/providers/sync_providers.dart';
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
  int dropboxCalls = 0;
  int gdriveCalls = 0;
  int icloudCalls = 0;

  static const _result = MediaStoreConnectResult(
    storeId: 'store-x',
    createdNewStore: true,
  );

  @override
  Future<MediaStoreConnectResult> connectS3(S3Config config) async {
    connectCalls++;
    return _result;
  }

  @override
  Future<MediaStoreConnectResult> connectDropbox() async {
    dropboxCalls++;
    return _result;
  }

  @override
  Future<MediaStoreConnectResult> connectGoogleDrive() async {
    gdriveCalls++;
    return _result;
  }

  @override
  Future<MediaStoreConnectResult> connectICloud() async {
    icloudCalls++;
    return _result;
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

  Widget app({bool apple = true}) => ProviderScope(
    overrides: [
      mediaStoreRuntimeProvider.overrideWith((ref) async => null),
      mediaStoreCredentialsStoreProvider.overrideWithValue(
        MediaStoreCredentialsStore(storage: InMemoryKeychain()),
      ),
      mediaStoreServiceProvider.overrideWithValue(service),
      isApplePlatformProvider.overrideWithValue(apple),
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
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('media-s3-connect')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });

    expect(service.connectCalls, 1);
  });

  testWidgets('chooser defaults to S3 with the form visible', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(app());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });

    expect(find.byKey(const Key('media-provider-chooser')), findsOneWidget);
    expect(find.byKey(const Key('media-s3-endpoint')), findsOneWidget);
    expect(find.text('iCloud'), findsOneWidget);
    expect(find.byKey(const Key('media-dropbox-connect')), findsNothing);
  });

  testWidgets('selecting dropbox swaps the form for the connect panel '
      'and calls the service', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(app());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });

    await tester.tap(find.text('Dropbox'));
    await tester.pump();

    expect(find.byKey(const Key('media-s3-endpoint')), findsNothing);
    expect(find.byKey(const Key('media-dropbox-connect')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('media-dropbox-connect')));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('media-dropbox-connect')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });

    expect(service.dropboxCalls, 1);
    expect(service.connectCalls, 0);
  });

  testWidgets('the iCloud segment is absent on non-Apple '
      'platforms', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(app(apple: false));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });

    expect(find.byKey(const Key('media-provider-chooser')), findsOneWidget);
    expect(find.text('iCloud'), findsNothing);
    expect(find.text('Google Drive'), findsOneWidget);
  });
}
