import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:submersion/core/services/cloud_storage/s3/s3_api_client.dart';
import 'package:submersion/core/services/local_cache_database_service.dart';
import 'package:submersion/core/services/media_store/media_object_store.dart';
import 'package:submersion/core/services/media_store/media_store_attach_state.dart';
import 'package:submersion/core/services/media_store/media_store_credentials_store.dart';
import 'package:submersion/core/services/media_store/s3_media_object_store.dart';
import 'package:submersion/core/services/media_store/store_marker.dart';
import 'package:submersion/features/media/data/resolvers/media_store_resolver.dart';
import 'package:submersion/features/media/presentation/providers/media_providers.dart';
import 'package:submersion/features/media/presentation/providers/media_resolver_providers.dart';
import 'package:submersion/features/media_store/data/media_cache_store.dart';
import 'package:submersion/features/media_store/data/media_store_worker.dart';
import 'package:submersion/features/media_store/data/media_transfer_queue_repository.dart';
import 'package:submersion/features/media_store/data/media_upload_pipeline.dart';

/// Everything a configured media store needs at runtime. Built once per
/// attach; disposed and rebuilt on connect/disconnect via provider
/// invalidation.
class MediaStoreRuntime {
  final String storeId;
  final MediaObjectStore store;
  final MediaCacheStore cache;
  final MediaStoreResolver resolver;
  final MediaStoreWorker? worker;

  const MediaStoreRuntime({
    required this.storeId,
    required this.store,
    required this.cache,
    required this.resolver,
    this.worker,
  });
}

final mediaStoreCredentialsStoreProvider = Provider<MediaStoreCredentialsStore>(
  (ref) => MediaStoreCredentialsStore(),
);

final mediaStoreAttachStateProvider = Provider<MediaStoreAttachState>(
  (ref) => MediaStoreAttachState(),
);

/// The configured media store runtime, or null when this device has no
/// store attached. Lazy: the first watcher (a media view or the settings
/// page) triggers construction and a queue drain. Invalidate after connect
/// or disconnect.
final mediaStoreRuntimeProvider = FutureProvider<MediaStoreRuntime?>((
  ref,
) async {
  final config = await ref.watch(mediaStoreCredentialsStoreProvider).load();
  if (config == null) return null;
  final attachedId = await ref
      .watch(mediaStoreAttachStateProvider)
      .attachedStoreId();
  if (attachedId == null) return null;

  final client = S3ApiClient(config);
  ref.onDispose(client.close);
  final store = S3MediaObjectStore(client: client, keyPrefix: config.prefix);

  final supportDir = await getApplicationSupportDirectory();
  final cache = MediaCacheStore(
    database: LocalCacheDatabaseService.instance.database,
    root: Directory(p.join(supportDir.path, 'Submersion', 'media_cache')),
  );
  final resolver = MediaStoreResolver(store: store, cache: cache);

  final pipeline = MediaUploadPipeline(
    mediaRepository: ref.watch(mediaRepositoryProvider),
    queue: MediaTransferQueueRepository(),
    store: store,
    registry: ref.watch(mediaSourceResolverRegistryProvider),
    cache: cache,
  );
  final worker = MediaStoreWorker(
    queue: MediaTransferQueueRepository(),
    pipeline: pipeline,
    preflight: () async {
      // Suspend all transfers when the bucket no longer carries the store
      // this device attached to (wiped or repointed; spec section 13).
      final marker = await StoreMarkerStore(store: store).read();
      return marker != null && marker.storeId == attachedId;
    },
  );
  unawaited(worker.drain());

  return MediaStoreRuntime(
    storeId: attachedId,
    store: store,
    cache: cache,
    resolver: resolver,
    worker: worker,
  );
});

/// The store-fallback resolver for display surfaces, or null when no store
/// runtime exists yet. Synchronous accessor over the async runtime.
final mediaStoreResolverProvider = Provider<MediaStoreResolver?>((ref) {
  return ref.watch(mediaStoreRuntimeProvider).value?.resolver;
});

/// Implementation behind mediaStoreEnqueueProvider: with a runtime
/// attached, imports feed the queue and kick the worker; without one this
/// is a no-op.
final mediaStoreEnqueueImplProvider = Provider<void Function(String)>((ref) {
  return (mediaId) {
    unawaited(() async {
      final runtime = await ref.read(mediaStoreRuntimeProvider.future);
      await runtime?.worker?.enqueueAndKick(mediaId);
    }());
  };
});
