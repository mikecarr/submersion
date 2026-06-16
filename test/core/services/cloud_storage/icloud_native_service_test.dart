import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/services/cloud_storage/icloud_native_service.dart';

void main() {
  group('ICloudNativeService.availabilityFromStatus', () {
    test('maps "available"', () {
      expect(
        ICloudNativeService.availabilityFromStatus('available'),
        ICloudAvailability.available,
      );
    });

    test('maps "signedOut"', () {
      expect(
        ICloudNativeService.availabilityFromStatus('signedOut'),
        ICloudAvailability.signedOut,
      );
    });

    test('maps "unsupported"', () {
      expect(
        ICloudNativeService.availabilityFromStatus('unsupported'),
        ICloudAvailability.unsupported,
      );
    });

    test('maps an unrecognized string to unknown', () {
      expect(
        ICloudNativeService.availabilityFromStatus('wat'),
        ICloudAvailability.unknown,
      );
    });

    test('maps null to unknown', () {
      expect(
        ICloudNativeService.availabilityFromStatus(null),
        ICloudAvailability.unknown,
      );
    });
  });
}
