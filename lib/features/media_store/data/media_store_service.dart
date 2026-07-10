import 'dart:io';

import 'package:submersion/core/services/cloud_storage/s3/s3_api_client.dart';
import 'package:submersion/core/services/cloud_storage/s3/s3_config.dart';
import 'package:submersion/core/services/media_store/media_object_store.dart';
import 'package:submersion/core/services/media_store/media_store_attach_state.dart';
import 'package:submersion/core/services/media_store/media_store_credentials_store.dart';
import 'package:submersion/core/services/media_store/s3_media_object_store.dart';
import 'package:submersion/core/services/media_store/store_marker.dart';
import 'package:submersion/features/media_store/data/media_stores_repository.dart';

class MediaStoreConnectResult {
  final String storeId;
  final bool createdNewStore;

  const MediaStoreConnectResult({
    required this.storeId,
    required this.createdNewStore,
  });
}

/// Connect/test/disconnect flows for the media store (design spec
/// sections 13-14). Owns no long-lived state; the runtime provider is
/// invalidated after these calls and rebuilds from persisted config.
class MediaStoreService {
  MediaStoreService({
    required MediaStoreCredentialsStore credentials,
    required MediaStoreAttachState attachState,
    required MediaStoresRepository storesRepository,
    MediaObjectStore Function(S3Config config)? storeFactory,
  }) : _credentials = credentials,
       _attachState = attachState,
       _storesRepository = storesRepository,
       _storeFactory = storeFactory ?? _defaultStoreFactory;

  final MediaStoreCredentialsStore _credentials;
  final MediaStoreAttachState _attachState;
  final MediaStoresRepository _storesRepository;
  final MediaObjectStore Function(S3Config config) _storeFactory;

  static MediaObjectStore _defaultStoreFactory(S3Config config) =>
      S3MediaObjectStore(client: S3ApiClient(config), keyPrefix: config.prefix);

  /// Live write+read-back+delete probe against the unsaved [config].
  /// Throws MediaStoreException on failure.
  Future<void> testConnection(S3Config config) async {
    _validate(config);
    final store = _storeFactory(config);
    const probeKey = 'smv1/.submersion-media-probe';
    final tmp = await _tempFile('probe');
    try {
      await tmp.writeAsString('probe', flush: true);
      await store.putFile(probeKey, tmp, contentType: 'text/plain');
      final info = await store.head(probeKey);
      if (info == null) {
        throw const MediaStoreException(
          'Probe object vanished after write',
          kind: MediaStoreErrorKind.fatal,
        );
      }
    } finally {
      try {
        await store.delete(probeKey);
      } on MediaStoreException {
        // Best-effort cleanup; a stranded probe object is harmless.
      }
      if (await tmp.exists()) await tmp.delete();
    }
  }

  /// Ensures the bucket carries a store marker (adopting an existing one),
  /// persists credentials and attach state, and announces the store in the
  /// synced descriptor table.
  Future<MediaStoreConnectResult> connectS3(S3Config config) async {
    _validate(config);
    final store = _storeFactory(config);
    final ensured = await StoreMarkerStore(store: store).ensure();
    await _credentials.save(config);
    await _attachState.setAttached(ensured.marker.storeId);
    await _storesRepository.upsertActive(
      storeId: ensured.marker.storeId,
      providerType: 's3',
      displayHint: '${config.bucket} @ ${config.displayHost}',
    );
    return MediaStoreConnectResult(
      storeId: ensured.marker.storeId,
      createdNewStore: ensured.created,
    );
  }

  /// Detaches this device. Credentials and attach state are cleared; the
  /// synced descriptor row and everything in the bucket remain.
  Future<void> disconnect() async {
    await _credentials.clear();
    await _attachState.clear();
  }

  void _validate(S3Config config) {
    final error = config.validate();
    if (error != null) {
      throw MediaStoreException(error, kind: MediaStoreErrorKind.fatal);
    }
  }

  Future<File> _tempFile(String label) async {
    return File(
      '${Directory.systemTemp.path}/submersion_media_${label}_'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
  }
}
