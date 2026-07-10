import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:submersion/core/services/cloud_storage/s3/s3_config.dart';
import 'package:submersion/core/services/media_store/media_store_attach_state.dart';
import 'package:submersion/core/services/media_store/media_store_credentials_store.dart';

import '../../../support/fake_keychain_storage.dart';

void main() {
  test('save/load round-trips config under the media key', () async {
    final storage = InMemoryKeychain();
    final store = MediaStoreCredentialsStore(storage: storage);
    expect(await store.load(), isNull);

    await store.save(
      S3Config(
        endpoint: 'https://minio.example.com',
        bucket: 'dive-media',
        prefix: 'submersion-media/',
        accessKeyId: 'AK',
        secretAccessKey: 'SK',
      ),
    );

    final loaded = await store.load();
    expect(loaded!.bucket, 'dive-media');
    expect(loaded.prefix, 'submersion-media/');
    expect(loaded.secretAccessKey, 'SK');
    expect(MediaStoreCredentialsStore.storageKey, 'media_store_s3_config');

    await store.clear();
    expect(await store.load(), isNull);
  });

  test('attach state round-trips via SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final state = MediaStoreAttachState(prefs: prefs);
    expect(await state.attachedStoreId(), isNull);
    await state.setAttached('store-xyz');
    expect(await state.attachedStoreId(), 'store-xyz');
    await state.clear();
    expect(await state.attachedStoreId(), isNull);
  });
}
