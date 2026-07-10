import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:submersion/core/services/cloud_storage/s3/s3_config.dart';
import 'package:submersion/core/services/media_store/media_object_store.dart';
import 'package:submersion/core/services/media_store/media_store_attach_state.dart';
import 'package:submersion/core/services/media_store/media_store_credentials_store.dart';
import 'package:submersion/features/media_store/data/media_store_service.dart';
import 'package:submersion/features/media_store/data/media_stores_repository.dart';

import '../../helpers/in_memory_media_object_store.dart';
import '../../helpers/test_database.dart';
import '../../support/fake_keychain_storage.dart';

void main() {
  late InMemoryMediaObjectStore fakeStore;
  late MediaStoreCredentialsStore credentials;
  late MediaStoreAttachState attachState;
  late MediaStoresRepository storesRepository;
  late MediaStoreService service;

  final config = S3Config(
    endpoint: 'https://minio.example.com',
    bucket: 'dive-media',
    prefix: 'submersion-media/',
    accessKeyId: 'AK',
    secretAccessKey: 'SK',
  );

  setUp(() async {
    await setUpTestDatabase();
    SharedPreferences.setMockInitialValues({});
    fakeStore = InMemoryMediaObjectStore();
    credentials = MediaStoreCredentialsStore(storage: InMemoryKeychain());
    attachState = MediaStoreAttachState(
      prefs: await SharedPreferences.getInstance(),
    );
    storesRepository = MediaStoresRepository();
    service = MediaStoreService(
      credentials: credentials,
      attachState: attachState,
      storesRepository: storesRepository,
      storeFactory: (_) => fakeStore,
    );
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  test('connectS3 creates the marker, attaches, and writes the '
      'descriptor', () async {
    final result = await service.connectS3(config);
    expect(result.createdNewStore, isTrue);
    expect(fakeStore.objects.containsKey('smv1/store.json'), isTrue);
    expect(await attachState.attachedStoreId(), result.storeId);
    final active = await storesRepository.getActive();
    expect(active!.providerType, 's3');
    expect(active.displayHint, contains('dive-media'));
    expect(await credentials.load(), isNotNull);
  });

  test('connectS3 against an existing store adopts its storeId', () async {
    final first = await service.connectS3(config);
    await service.disconnect();
    final second = await service.connectS3(config);
    expect(second.createdNewStore, isFalse);
    expect(second.storeId, first.storeId);
  });

  test('testConnection round-trips a probe object and cleans up', () async {
    await service.testConnection(config);
    expect(fakeStore.objects.keys.where((k) => k.contains('probe')), isEmpty);
  });

  test('invalid config throws before touching the store', () async {
    final bad = S3Config(
      endpoint: 'https://minio.example.com',
      bucket: '',
      accessKeyId: 'AK',
      secretAccessKey: 'SK',
    );
    await expectLater(
      service.connectS3(bad),
      throwsA(isA<MediaStoreException>()),
    );
    expect(fakeStore.objects, isEmpty);
  });

  test('disconnect clears credentials and attach state', () async {
    await service.connectS3(config);
    await service.disconnect();
    expect(await credentials.load(), isNull);
    expect(await attachState.attachedStoreId(), isNull);
  });
}
