import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/services/secure_storage/fallback_secure_storage.dart';

import '../../../support/fake_keychain_storage.dart';

void main() {
  test(
    'read returns the primary keychain value without falling back',
    () async {
      final inner = InMemoryKeychain()..values['k'] = 'v';
      final storage = FallbackSecureStorage(inner);

      expect(await storage.read(key: 'k'), 'v');
    },
  );

  test(
    'read falls back to the legacy keychain on errSecMissingEntitlement',
    () async {
      final inner = NoEntitlementKeychain()..legacy['k'] = 'v';
      final storage = FallbackSecureStorage(inner);

      expect(await storage.read(key: 'k'), 'v');
      expect(inner.dataProtectionAttempted, isTrue);
    },
  );

  test(
    'write falls back to the legacy keychain on errSecMissingEntitlement',
    () async {
      final inner = NoEntitlementKeychain();
      final storage = FallbackSecureStorage(inner);

      await storage.write(key: 'k', value: 'v');

      expect(inner.legacy['k'], 'v');
    },
  );

  test(
    'delete falls back to the legacy keychain on errSecMissingEntitlement',
    () async {
      final inner = NoEntitlementKeychain()..legacy['k'] = 'v';
      final storage = FallbackSecureStorage(inner);

      await storage.delete(key: 'k');

      expect(inner.legacy.containsKey('k'), isFalse);
    },
  );

  test('a non-entitlement PlatformException propagates unchanged', () async {
    final storage = FallbackSecureStorage(FailingKeychain(-25308));

    expect(storage.read(key: 'k'), throwsA(isA<PlatformException>()));
  });
}
