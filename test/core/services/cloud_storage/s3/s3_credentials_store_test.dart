import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/services/cloud_storage/s3/s3_config.dart';
import 'package:submersion/core/services/cloud_storage/s3/s3_credentials_store.dart';

class _MemorySecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

class _ThrowingSecureStorage extends Fake implements FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw Exception('keychain locked');
}

/// Simulates an ad-hoc-signed, no-sandbox macOS build: the data-protection
/// keychain returns `errSecMissingEntitlement` (-34018) because the binary
/// carries no keychain access group, while the legacy file-based keychain
/// works. Lets the tests prove [S3CredentialsStore] retries on the legacy
/// keychain.
class _NoEntitlementSecureStorage extends Fake implements FlutterSecureStorage {
  /// Backing store standing in for the legacy (file-based) keychain.
  final Map<String, String> legacy = {};

  /// Set once the data-protection keychain has been attempted, proving the
  /// store prefers the secure keychain before falling back.
  bool dataProtectionAttempted = false;

  static const int _errSecMissingEntitlement = -34018;

  bool _usesDataProtection(AppleOptions? mOptions) =>
      (mOptions as MacOsOptions?)?.usesDataProtectionKeychain ?? true;

  PlatformException _missingEntitlement() => PlatformException(
    code: 'Unexpected security result code',
    message: "A required entitlement isn't present.",
    details: _errSecMissingEntitlement,
  );

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (_usesDataProtection(mOptions)) {
      dataProtectionAttempted = true;
      throw _missingEntitlement();
    }
    return legacy[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (_usesDataProtection(mOptions)) {
      dataProtectionAttempted = true;
      throw _missingEntitlement();
    }
    if (value == null) {
      legacy.remove(key);
    } else {
      legacy[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (_usesDataProtection(mOptions)) {
      dataProtectionAttempted = true;
      throw _missingEntitlement();
    }
    legacy.remove(key);
  }
}

/// Throws a keychain [PlatformException] whose status is NOT the
/// missing-entitlement code, proving the fallback rethrows it untouched.
class _OtherSecurityErrorStorage extends Fake implements FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw PlatformException(
    code: 'Unexpected security result code',
    message: 'interaction not allowed',
    details: -25308, // errSecInteractionNotAllowed
  );
}

void main() {
  late _MemorySecureStorage storage;
  late S3CredentialsStore store;

  setUp(() {
    storage = _MemorySecureStorage();
    store = S3CredentialsStore(storage: storage);
  });

  S3Config config() => S3Config(
    endpoint: 'http://nas.local:9000',
    bucket: 'dive-sync',
    accessKeyId: 'ak',
    secretAccessKey: 'sk',
  );

  test('load returns null when nothing is stored', () async {
    expect(await store.load(), isNull);
  });

  test('save then load round-trips the config', () async {
    await store.save(config());
    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.endpoint, 'http://nas.local:9000');
    expect(loaded.bucket, 'dive-sync');
    expect(loaded.secretAccessKey, 'sk');
    expect(storage.values.keys, [S3CredentialsStore.storageKey]);
  });

  test('clear removes the blob', () async {
    await store.save(config());
    await store.clear();
    expect(await store.load(), isNull);
    expect(storage.values, isEmpty);
  });

  test('corrupted JSON loads as null instead of throwing', () async {
    storage.values[S3CredentialsStore.storageKey] = 'not-json{';
    expect(await store.load(), isNull);
  });

  test('valid JSON that is not an object loads as null', () async {
    storage.values[S3CredentialsStore.storageKey] = '[]';
    expect(await store.load(), isNull);
  });

  test('an object with wrong-typed fields loads as null', () async {
    storage.values[S3CredentialsStore.storageKey] = '{"endpoint": 1}';
    expect(await store.load(), isNull);
  });

  test('storage errors propagate to the caller', () async {
    final throwingStore = S3CredentialsStore(storage: _ThrowingSecureStorage());
    expect(throwingStore.load(), throwsA(isA<Exception>()));
  });

  group('keychain entitlement fallback', () {
    test('load falls back to the legacy keychain when the data-protection '
        'keychain reports errSecMissingEntitlement', () async {
      final storage = _NoEntitlementSecureStorage();
      storage.legacy[S3CredentialsStore.storageKey] = jsonEncode(
        config().toJson(),
      );
      final fallbackStore = S3CredentialsStore(storage: storage);

      final loaded = await fallbackStore.load();

      expect(
        storage.dataProtectionAttempted,
        isTrue,
        reason: 'the secure keychain must be tried before the legacy one',
      );
      expect(loaded, isNotNull);
      expect(loaded!.bucket, 'dive-sync');
    });

    test(
      'save falls back to the legacy keychain on errSecMissingEntitlement',
      () async {
        final storage = _NoEntitlementSecureStorage();
        final fallbackStore = S3CredentialsStore(storage: storage);

        await fallbackStore.save(config());

        expect(
          storage.legacy.containsKey(S3CredentialsStore.storageKey),
          isTrue,
        );
      },
    );

    test(
      'a non-entitlement PlatformException is not swallowed by the fallback',
      () async {
        final failingStore = S3CredentialsStore(
          storage: _OtherSecurityErrorStorage(),
        );

        expect(failingStore.load(), throwsA(isA<PlatformException>()));
      },
    );
  });
}
