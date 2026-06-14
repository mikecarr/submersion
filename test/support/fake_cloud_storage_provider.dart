import 'dart:typed_data';

import 'package:submersion/core/services/cloud_storage/cloud_storage_provider.dart';

/// In-memory CloudStorageProvider for deterministic sync tests. Keys are
/// "<folderId>/<filename>". A monotonic counter stands in for modified time so
/// tests never depend on the wall clock. Optionally simulates list lag (a
/// just-written file invisible to listFiles for N calls) to exercise the
/// eventual-consistency / transient-missing paths in later phases.
class FakeCloudStorageProvider implements CloudStorageProvider {
  FakeCloudStorageProvider({this.providerId = 's3', this.listLagCalls = 0});

  @override
  final String providerId;

  /// Number of listFiles calls during which a freshly-written key stays hidden.
  final int listLagCalls;

  static const String _folder = 'sync';

  final Map<String, Uint8List> _files = {};
  final Map<String, int> _modified = {};
  final Map<String, int> _visibleAfterCall = {};
  int _clock = 0;
  int _listCalls = 0;

  @override
  String get providerName => 'Fake ($providerId)';

  String _key(String? folder, String name) => '${folder ?? _folder}/$name';

  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<bool> isAuthenticated() async => true;
  @override
  Future<void> authenticate() async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<String?> getUserEmail() async => 'test@example.com';
  @override
  Future<String> getOrCreateSyncFolder() async => _folder;

  @override
  Future<String> createFolder(
    String folderName, {
    String? parentFolderId,
  }) async =>
      parentFolderId == null ? folderName : '$parentFolderId/$folderName';

  @override
  Future<UploadResult> uploadFile(
    Uint8List data,
    String filename, {
    String? folderId,
  }) async {
    final key = _key(folderId, filename);
    _files[key] = Uint8List.fromList(data);
    _modified[key] = ++_clock;
    if (listLagCalls > 0) _visibleAfterCall[key] = _listCalls + listLagCalls;
    return UploadResult(
      fileId: key,
      uploadTime: DateTime.fromMillisecondsSinceEpoch(_clock),
    );
  }

  @override
  Future<Uint8List> downloadFile(String fileId) async {
    final data = _files[fileId];
    if (data == null) {
      throw CloudStorageException('Fake: not found: $fileId');
    }
    return Uint8List.fromList(data);
  }

  @override
  Future<List<CloudFileInfo>> listFiles({
    String? folderId,
    String? namePattern,
  }) async {
    final call = ++_listCalls;
    final folder = folderId ?? _folder;
    final out = <CloudFileInfo>[];
    for (final entry in _files.entries) {
      final visibleAt = _visibleAfterCall[entry.key];
      if (visibleAt != null && call < visibleAt) continue;
      final slash = entry.key.indexOf('/');
      final f = entry.key.substring(0, slash);
      final name = entry.key.substring(slash + 1);
      if (f != folder) continue;
      if (namePattern != null && !name.contains(namePattern)) continue;
      out.add(
        CloudFileInfo(
          id: entry.key,
          name: name,
          modifiedTime: DateTime.fromMillisecondsSinceEpoch(
            _modified[entry.key]!,
          ),
          sizeBytes: entry.value.length,
        ),
      );
    }
    return out;
  }

  @override
  Future<void> deleteFile(String fileId) async {
    _files.remove(fileId);
    _modified.remove(fileId);
    _visibleAfterCall.remove(fileId);
  }

  @override
  Future<bool> fileExists(String fileId) async => _files.containsKey(fileId);

  @override
  Future<CloudFileInfo?> getFileInfo(String fileId) async {
    final data = _files[fileId];
    if (data == null) return null;
    final slash = fileId.indexOf('/');
    return CloudFileInfo(
      id: fileId,
      name: fileId.substring(slash + 1),
      modifiedTime: DateTime.fromMillisecondsSinceEpoch(_modified[fileId]!),
      sizeBytes: data.length,
    );
  }
}
