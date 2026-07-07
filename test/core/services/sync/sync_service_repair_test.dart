import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:submersion/core/data/repositories/sync_repository.dart';
import 'package:submersion/core/services/database_service.dart';
import 'package:submersion/core/services/sync/library_epoch.dart';
import 'package:submersion/core/services/sync/library_epoch_store.dart';
import 'package:submersion/core/services/sync/sync_data_serializer.dart';
import 'package:submersion/core/services/sync/sync_service.dart';

import '../../../helpers/fake_cloud_storage_provider.dart';
import '../../../helpers/test_database.dart';

/// Issue #509: the comprehensive local Repair. resetSyncState already clears
/// the DB-side sync state; Repair adds the one thing it misses -- the
/// SharedPreferences epoch markers -- plus a sweep of leftover base temp files.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LibraryEpochStore epochStore;
  late FakeCloudStorageProvider cloud;
  late Directory fakeAppTemp;

  setUpAll(() async {
    fakeAppTemp = await Directory.systemTemp.createTemp('repair_app_temp_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async =>
              call.method == 'getTemporaryDirectory' ? fakeAppTemp.path : null,
        );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (fakeAppTemp.existsSync()) await fakeAppTemp.delete(recursive: true);
  });

  setUp(() async {
    await setUpTestDatabase();
    SharedPreferences.setMockInitialValues({});
    epochStore = LibraryEpochStore(await SharedPreferences.getInstance());
    cloud = FakeCloudStorageProvider();
  });

  tearDown(() => DatabaseService.instance.resetForTesting());

  SyncService buildService() => SyncService(
    syncRepository: SyncRepository(),
    serializer: SyncDataSerializer(),
    cloudProvider: cloud,
    epochStore: epochStore,
  );

  test(
    'repairLocalSyncState clears the epoch store and leftover base temp files',
    () async {
      const marker = LibraryEpochMarker(
        epochId: 'e1',
        replacedAt: 1,
        deviceId: 'd1',
      );
      await epochStore.setLastAccepted(marker);
      await epochStore.setPendingReplace(marker);
      final leftover = File('${fakeAppTemp.path}/ssv1_base_dev_0.abc.json');
      await leftover.writeAsString('stale');

      await buildService().repairLocalSyncState();

      expect(epochStore.lastAcceptedMarker, isNull);
      expect(epochStore.pendingReplace, isNull);
      expect(leftover.existsSync(), isFalse);
    },
  );
}
