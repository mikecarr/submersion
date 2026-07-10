import 'package:submersion/core/services/logger_service.dart';
import 'package:submersion/core/services/media_store/media_object_store.dart';
import 'package:submersion/core/services/media_store/store_keys.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/domain/value_objects/media_source_data.dart';
import 'package:submersion/features/media_store/data/media_cache_store.dart';

/// Store-backed fallback resolution (design spec section 10). Deliberately
/// NOT a MediaSourceResolver and never registered under a MediaSourceType:
/// rows keep their native source type, so disconnecting the store degrades
/// every row to exactly the pre-store behavior.
class MediaStoreResolver {
  MediaStoreResolver({
    required MediaObjectStore store,
    required MediaCacheStore cache,
  }) : _store = store,
       _cache = cache;

  final MediaObjectStore _store;
  final MediaCacheStore _cache;
  final _log = LoggerService.forClass(MediaStoreResolver);

  /// Phase 1 ignores [thumbnail] (no thumb objects yet); full originals
  /// serve both roles. Phase 2 routes thumbnail requests to thumb keys.
  ///
  /// Returns FileData when the bytes are cached or fetched-and-verified;
  /// null when this item is not confirmed in the store or any error occurs
  /// (the caller keeps its native UnavailableData).
  Future<MediaSourceData?> tryResolveRemote(
    MediaItem item, {
    required bool thumbnail,
  }) async {
    final hash = item.contentHash;
    if (hash == null || item.remoteUploadedAt == null) return null;
    try {
      final cached = await _cache.get(hash, MediaCacheKind.original);
      if (cached != null) return FileData(file: cached);

      final staging = await _cache.stagingFile();
      final extension = StoreKeys.extensionFor(item.originalFilename);
      await _store.getFile(
        StoreKeys.objectKey(hash, extension: extension),
        staging,
      );
      final digest = await sha256OfFile(staging);
      if (digest.hash != hash) {
        _log.warning('Store object failed hash verification for ${item.id}');
        await staging.delete();
        return null;
      }
      final file = await _cache.put(hash, MediaCacheKind.original, staging);
      return FileData(file: file);
    } on Exception catch (e) {
      _log.warning('Store fallback failed for ${item.id}: $e');
      return null;
    }
  }
}
