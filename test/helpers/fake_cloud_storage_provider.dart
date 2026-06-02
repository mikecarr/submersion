import 'dart:typed_data';

import 'package:submersion/core/services/cloud_storage/cloud_storage_provider.dart';

/// In-memory [CloudStorageProvider] for tests. Files are keyed by name, so the
/// canonical sync file maps to a single stable id across uploads.
class FakeCloudStorageProvider extends CloudStorageProvider
    with CloudStorageProviderMixin {
  final Map<String, _FakeFile> _files = {};
  bool authenticated = true;
  bool available = true;

  int get fileCount => _files.length;
  Uint8List? bytesOf(String name) => _files[name]?.data;

  @override
  String get providerName => 'Fake';

  @override
  String get providerId => 'fake';

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> isAuthenticated() async => authenticated;

  @override
  Future<void> authenticate() async {
    authenticated = true;
  }

  @override
  Future<void> signOut() async {
    authenticated = false;
  }

  @override
  Future<String?> getUserEmail() async => 'tester@example.com';

  @override
  Future<UploadResult> uploadFile(
    Uint8List data,
    String filename, {
    String? folderId,
  }) async {
    _files[filename] = _FakeFile(data, DateTime.now());
    return UploadResult(
      fileId: filename,
      uploadTime: _files[filename]!.modified,
    );
  }

  @override
  Future<Uint8List> downloadFile(String fileId) async {
    final f = _files[fileId];
    if (f == null) {
      throw CloudStorageException('File not found: $fileId');
    }
    return f.data;
  }

  @override
  Future<CloudFileInfo?> getFileInfo(String fileId) async {
    final f = _files[fileId];
    if (f == null) return null;
    return CloudFileInfo(
      id: fileId,
      name: fileId,
      modifiedTime: f.modified,
      sizeBytes: f.data.length,
    );
  }

  @override
  Future<List<CloudFileInfo>> listFiles({
    String? folderId,
    String? namePattern,
  }) async {
    return _files.entries
        .where((e) => namePattern == null || e.key.contains(namePattern))
        .map(
          (e) => CloudFileInfo(
            id: e.key,
            name: e.key,
            modifiedTime: e.value.modified,
            sizeBytes: e.value.data.length,
          ),
        )
        .toList();
  }

  @override
  Future<void> deleteFile(String fileId) async {
    _files.remove(fileId);
  }

  @override
  Future<bool> fileExists(String fileId) async => _files.containsKey(fileId);

  @override
  Future<String> createFolder(
    String folderName, {
    String? parentFolderId,
  }) async => 'fake-folder';

  @override
  Future<String> getOrCreateSyncFolder() async => 'fake-sync-folder';
}

class _FakeFile {
  final Uint8List data;
  final DateTime modified;
  _FakeFile(this.data, this.modified);
}
