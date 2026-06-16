import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A thin wrapper over [FlutterSecureStorage] that transparently retries on
/// the macOS legacy (file-based) keychain when the default data-protection
/// keychain reports `errSecMissingEntitlement` (-34018).
///
/// That status occurs on the ad-hoc-signed no-sandbox (GitHub-distribution)
/// build, whose signature carries no team `application-identifier` and hence
/// no keychain access group. Sandboxed / team-signed / iOS builds never hit
/// it, so the first attempt -- byte-identical to a plain [FlutterSecureStorage]
/// call -- succeeds and no fallback runs. `mOptions` is ignored on non-macOS
/// platforms, so wrapping is cross-platform-safe.
///
/// Only the missing-entitlement status triggers the retry; every other
/// keychain error propagates, so a locked keychain is never misread.
class FallbackSecureStorage {
  FallbackSecureStorage(this._storage);

  final FlutterSecureStorage _storage;

  /// `errSecMissingEntitlement` -- "a required entitlement isn't present".
  static const int _errSecMissingEntitlement = -34018;

  /// Selects the legacy file-based keychain on the retry.
  static const MacOsOptions _legacyKeychain = MacOsOptions(
    usesDataProtectionKeychain: false,
  );

  Future<String?> read({required String key}) => _withFallback(
    () => _storage.read(key: key),
    () => _storage.read(key: key, mOptions: _legacyKeychain),
  );

  Future<void> write({required String key, required String value}) =>
      _withFallback(
        () => _storage.write(key: key, value: value),
        () => _storage.write(key: key, value: value, mOptions: _legacyKeychain),
      );

  Future<void> delete({required String key}) => _withFallback(
    () => _storage.delete(key: key),
    () => _storage.delete(key: key, mOptions: _legacyKeychain),
  );

  /// Runs [primary] (the default data-protection keychain) and, only when it
  /// throws `errSecMissingEntitlement`, runs [legacy] (the file-based
  /// keychain) instead. The first attempt is awaited so its [PlatformException]
  /// surfaces inside the try rather than escaping as a rejected future.
  Future<T> _withFallback<T>(
    Future<T> Function() primary,
    Future<T> Function() legacy,
  ) async {
    try {
      return await primary();
    } on PlatformException catch (e) {
      if (e.details == _errSecMissingEntitlement) {
        return legacy();
      }
      rethrow;
    }
  }
}
