import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:submersion/core/services/cloud_storage/encrypting_cloud_storage_provider.dart';
import 'package:submersion/core/services/sync/crypto/keyslots.dart';
import 'package:submersion/core/services/sync/crypto/sync_envelope.dart';

import '../../../support/fake_cloud_storage_provider.dart';

const _keyId = '8f14e45f-ceea-467f-ab37-a10a8d5f4c11';

void main() {
  late FakeCloudStorageProvider inner;
  late EncryptingCloudStorageProvider provider;
  final dataKey = SecretKey(List<int>.generate(32, (i) => i + 1));

  setUp(() {
    inner = FakeCloudStorageProvider();
    provider = EncryptingCloudStorageProvider(
      inner,
      dataKey: dataKey,
      libraryKeyId: _keyId,
    );
  });

  Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

  test('uploads are SBE1 at rest, downloads round-trip plaintext', () async {
    final up = await provider.uploadFile(
      bytesOf('{"cs":1}'),
      'ssv1.devA.cs.00001.json',
    );
    // At rest (inner fake) the bytes must be an envelope:
    final atRest = await inner.downloadFile(up.fileId);
    expect(SyncEnvelope.hasMagic(atRest), isTrue);
    // Through the decorator they come back as plaintext:
    final roundTrip = await provider.downloadFile(up.fileId);
    expect(utf8.decode(roundTrip), '{"cs":1}');
  });

  test('keyslot file and backup artifacts are exempt', () async {
    expect(
      EncryptingCloudStorageProvider.isExempt(KeyslotFile.cloudFileName),
      isTrue,
    );
    expect(
      EncryptingCloudStorageProvider.isExempt(
        'submersion_backup_2026-07-10.sbe',
      ),
      isTrue,
    );
    expect(
      EncryptingCloudStorageProvider.isExempt('ssv1.devA.manifest.json'),
      isFalse,
    );

    final up = await provider.uploadFile(
      bytesOf('{"slots":[]}'),
      KeyslotFile.cloudFileName,
    );
    final atRest = await inner.downloadFile(up.fileId);
    expect(SyncEnvelope.hasMagic(atRest), isFalse);
    expect(utf8.decode(atRest), '{"slots":[]}');
  });

  test('plaintext files pass through downloads unchanged', () async {
    final up = await inner.uploadFile(
      bytesOf('{"legacy":true}'),
      'submersion_library_epoch.json',
    );
    final viaDecorator = await provider.downloadFile(up.fileId);
    expect(utf8.decode(viaDecorator), '{"legacy":true}');
  });

  test('download resolves filename via listFiles for AAD', () async {
    await provider.uploadFile(bytesOf('{"m":1}'), 'ssv1.devB.manifest.json');
    // fresh decorator instance = empty name cache; it must list or getFileInfo
    final fresh = EncryptingCloudStorageProvider(
      inner,
      dataKey: dataKey,
      libraryKeyId: _keyId,
    );
    final files = await fresh.listFiles(namePattern: 'ssv1.');
    final m = files.singleWhere((f) => f.name == 'ssv1.devB.manifest.json');
    final bytes = await fresh.downloadFile(m.id);
    expect(utf8.decode(bytes), '{"m":1}');
  });

  test('download with cold cache falls back to getFileInfo', () async {
    final up = await provider.uploadFile(
      bytesOf('{"cold":true}'),
      'ssv1.devC.cs.00001.json',
    );
    final fresh = EncryptingCloudStorageProvider(
      inner,
      dataKey: dataKey,
      libraryKeyId: _keyId,
    );
    // No listFiles call first: must resolve the name via getFileInfo.
    final bytes = await fresh.downloadFile(up.fileId);
    expect(utf8.decode(bytes), '{"cold":true}');
  });

  test('delegates providerName/providerId and deleteFile', () async {
    expect(provider.providerId, inner.providerId);
    expect(provider.providerName, inner.providerName);
    final up = await provider.uploadFile(bytesOf('x'), 'ssv1.devA.cs.1.json');
    await provider.deleteFile(up.fileId);
    expect(await inner.fileExists(up.fileId), isFalse);
  });
}
