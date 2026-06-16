import 'dart:io';

import 'package:flutter/services.dart';

import 'package:submersion/core/services/logger_service.dart';

/// Runtime iCloud availability for the current build/device.
///
/// `unsupported` means this build lacks the iCloud (ubiquity-container)
/// entitlement — e.g. a Developer ID / no-sandbox distribution build — so
/// iCloud can never work here regardless of the user's iCloud account.
enum ICloudAvailability { available, signedOut, unsupported, unknown }

/// Platform channel helpers for iCloud container access and file download.
class ICloudNativeService {
  static const MethodChannel _channel = MethodChannel(
    'app.submersion/icloud_container',
  );
  static final _log = LoggerService.forClass(ICloudNativeService);

  static const String containerIdentifier = 'iCloud.app.submersion';

  /// Returns the iCloud container Documents directory, or null if unavailable.
  static Future<String?> getContainerPath() async {
    if (!Platform.isIOS && !Platform.isMacOS) return null;
    try {
      final path = await _channel.invokeMethod<String>(
        'getICloudContainerPath',
        {'identifier': containerIdentifier},
      );
      return path;
    } catch (e, stackTrace) {
      _log.warning(
        'Failed to get iCloud container path: $e',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Pure mapping from the native status string to [ICloudAvailability].
  /// Extracted so it can be unit-tested independently of `dart:io` Platform.
  static ICloudAvailability availabilityFromStatus(String? status) {
    return switch (status) {
      'available' => ICloudAvailability.available,
      'signedOut' => ICloudAvailability.signedOut,
      'unsupported' => ICloudAvailability.unsupported,
      _ => ICloudAvailability.unknown,
    };
  }

  /// Reports iCloud availability for the current build/device.
  ///
  /// Non-blocking on the native side (it does not resolve the container URL),
  /// so it cannot hang. Returns [ICloudAvailability.unknown] on any channel
  /// error or unmirrored platform, which the UI treats optimistically.
  static Future<ICloudAvailability> getAvailability() async {
    if (!Platform.isIOS && !Platform.isMacOS) {
      return ICloudAvailability.unsupported;
    }
    try {
      final status = await _channel.invokeMethod<String>(
        'getICloudAvailability',
      );
      return availabilityFromStatus(status);
    } catch (e, stackTrace) {
      _log.warning(
        'Failed to get iCloud availability: $e',
        stackTrace: stackTrace,
      );
      return ICloudAvailability.unknown;
    }
  }

  /// Ensures the iCloud file is downloaded locally before access.
  static Future<bool> downloadIfNeeded(String path) async {
    if (!Platform.isIOS && !Platform.isMacOS) return true;
    try {
      final result = await _channel.invokeMethod<bool>('downloadIfNeeded', {
        'path': path,
      });
      return result ?? false;
    } catch (e, stackTrace) {
      _log.warning(
        'Failed to download iCloud file: $e',
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Writes data to the given path using native file coordination.
  /// Throws an exception with the error details if writing fails.
  static Future<void> writeFile(String path, Uint8List data) async {
    if (!Platform.isIOS && !Platform.isMacOS) {
      throw Exception('writeFile only supported on iOS/macOS');
    }
    _log.info('writeFile: path=$path, size=${data.length} bytes');
    final result = await _channel.invokeMethod<bool>('writeFile', {
      'path': path,
      'data': data,
    });
    if (result != true) {
      throw Exception('Native writeFile returned false');
    }
    _log.info('writeFile: success');
  }

  /// Refreshes an iCloud folder to ensure we see the latest files from other devices.
  /// This triggers downloads for any files that exist in iCloud but aren't local.
  static Future<void> refreshFolder(String path) async {
    if (!Platform.isIOS && !Platform.isMacOS) return;
    try {
      _log.info('refreshFolder: $path');
      await _channel.invokeMethod<bool>('refreshFolder', {'path': path});
      _log.info('refreshFolder: done');
    } catch (e, stackTrace) {
      _log.warning(
        'Failed to refresh iCloud folder: $e',
        stackTrace: stackTrace,
      );
      // Don't throw - folder refresh is best-effort
    }
  }

  /// Moves a local file into the iCloud container using native coordination.
  static Future<bool> moveFile(
    String sourcePath,
    String destinationPath,
  ) async {
    if (!Platform.isIOS && !Platform.isMacOS) return false;
    try {
      final result = await _channel.invokeMethod<bool>('moveFile', {
        'sourcePath': sourcePath,
        'destinationPath': destinationPath,
      });
      return result ?? false;
    } catch (e, stackTrace) {
      _log.warning('Failed to move iCloud file: $e', stackTrace: stackTrace);
      return false;
    }
  }
}
