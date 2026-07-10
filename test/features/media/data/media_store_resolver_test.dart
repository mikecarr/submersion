import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/local_cache_database.dart';
import 'package:submersion/core/services/media_store/store_keys.dart';
import 'package:submersion/features/media/data/resolvers/media_store_resolver.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/domain/entities/media_source_type.dart';
import 'package:submersion/features/media/domain/value_objects/media_source_data.dart';
import 'package:submersion/features/media_store/data/media_cache_store.dart';

import '../../../helpers/in_memory_media_object_store.dart';

void main() {
  late LocalCacheDatabase db;
  late Directory root;
  late InMemoryMediaObjectStore store;
  late MediaCacheStore cache;
  late MediaStoreResolver resolver;

  setUp(() async {
    db = LocalCacheDatabase(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('msr_test');
    store = InMemoryMediaObjectStore();
    cache = MediaCacheStore(database: db, root: root);
    resolver = MediaStoreResolver(store: store, cache: cache);
  });

  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  MediaItem item({String? hash, DateTime? uploadedAt}) => MediaItem(
    id: 'm1',
    mediaType: MediaType.photo,
    sourceType: MediaSourceType.platformGallery,
    platformAssetId: 'gone-from-this-device',
    originalFilename: 'reef.jpg',
    takenAt: DateTime(2026),
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    contentHash: hash,
    remoteUploadedAt: uploadedAt,
  );

  test('returns null without a confirmation stamp', () async {
    expect(
      await resolver.tryResolveRemote(item(hash: 'a' * 64), thumbnail: false),
      isNull,
    );
    expect(
      await resolver.tryResolveRemote(
        item(uploadedAt: DateTime(2026)),
        thumbnail: false,
      ),
      isNull,
    );
  });

  test('downloads, hash-verifies, caches, and returns FileData', () async {
    final bytes = 'submersion'.codeUnits;
    final tmp = File('${root.path}/seed');
    await tmp.writeAsBytes(bytes, flush: true);
    final digest = await sha256OfFile(tmp);
    store.objects[StoreKeys.objectKey(digest.hash, extension: 'jpg')] = bytes;

    final data = await resolver.tryResolveRemote(
      item(hash: digest.hash, uploadedAt: DateTime(2026)),
      thumbnail: false,
    );
    expect(data, isA<FileData>());
    expect(await (data! as FileData).file.readAsBytes(), bytes);

    // Second resolve is a pure cache hit even with an empty store.
    store.objects.clear();
    final again = await resolver.tryResolveRemote(
      item(hash: digest.hash, uploadedAt: DateTime(2026)),
      thumbnail: false,
    );
    expect(again, isA<FileData>());
  });

  test('hash mismatch is rejected and not cached', () async {
    final wrongHash = 'f' * 64;
    store.objects[StoreKeys.objectKey(wrongHash, extension: 'jpg')] =
        'tampered'.codeUnits;
    final data = await resolver.tryResolveRemote(
      item(hash: wrongHash, uploadedAt: DateTime(2026)),
      thumbnail: false,
    );
    expect(data, isNull);
    expect(await cache.get(wrongHash, MediaCacheKind.original), isNull);
  });

  test('store errors degrade to null', () async {
    store.failNextWith = Exception('boom');
    final data = await resolver.tryResolveRemote(
      item(hash: 'a' * 64, uploadedAt: DateTime(2026)),
      thumbnail: false,
    );
    expect(data, isNull);
  });
}
