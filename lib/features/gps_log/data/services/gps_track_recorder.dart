import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

import 'package:submersion/features/gps_log/data/repositories/gps_track_repository.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/domain/track_point_codec.dart';

enum GpsRecorderStatus { idle, recording }

class GpsRecorderState {
  final GpsRecorderStatus status;
  final String? trackId;
  final int pointCount;

  /// Real UTC, for elapsed-time display.
  final DateTime? startedAt;

  /// Real UTC time of the last accepted fix.
  final DateTime? lastFixAt;
  final double? lastFixAccuracy;

  const GpsRecorderState({
    this.status = GpsRecorderStatus.idle,
    this.trackId,
    this.pointCount = 0,
    this.startedAt,
    this.lastFixAt,
    this.lastFixAccuracy,
  });
}

/// Records a GPS surface track via a continuous geolocator stream.
///
/// Foreground-started; both platforms keep the stream alive in the
/// background under While-In-Use permission (iOS blue indicator via the
/// location background mode, Android foreground-service notification
/// supplied through [AndroidSettings.foregroundNotificationConfig]).
class GpsTrackRecorder {
  static const double maxAccuracyMeters = 100;
  static const int distanceFilterMeters = 20;

  final GpsTrackRepository _repository;
  final Stream<Position> Function(LocationSettings) _positionStreamFactory;
  final Duration _keepaliveInterval;
  final Duration _checkpointInterval;
  final Future<void> Function(String trackId)? _onTrackFinalized;

  final _stateController = StreamController<GpsRecorderState>.broadcast();
  GpsRecorderState _state = const GpsRecorderState();
  StreamSubscription<Position>? _subscription;
  Timer? _keepaliveTimer;
  Timer? _checkpointTimer;
  Position? _lastPosition;

  GpsTrackRecorder({
    required GpsTrackRepository repository,
    Stream<Position> Function(LocationSettings)? positionStreamFactory,
    Duration keepaliveInterval = const Duration(minutes: 5),
    Duration checkpointInterval = const Duration(minutes: 10),
    Future<void> Function(String trackId)? onTrackFinalized,
  }) : _repository = repository,
       _positionStreamFactory =
           positionStreamFactory ??
           ((settings) =>
               Geolocator.getPositionStream(locationSettings: settings)),
       _keepaliveInterval = keepaliveInterval,
       _checkpointInterval = checkpointInterval,
       _onTrackFinalized = onTrackFinalized;

  GpsRecorderState get state => _state;
  Stream<GpsRecorderState> get states => _stateController.stream;
  bool get isRecording => _state.status == GpsRecorderStatus.recording;

  Future<void> start({
    required String notificationTitle,
    required String notificationText,
  }) async {
    if (isRecording) return;
    final now = DateTime.now();
    final trackId = await _repository.startTrack(
      startTimeMs: toWallClockEpochSeconds(now.toUtc()) * 1000,
      tzOffsetMinutes: now.timeZoneOffset.inMinutes,
    );
    _setState(
      GpsRecorderState(
        status: GpsRecorderStatus.recording,
        trackId: trackId,
        startedAt: now.toUtc(),
      ),
    );
    _subscription = _positionStreamFactory(
      _buildSettings(notificationTitle, notificationText),
    ).listen(_onPosition, onError: (Object _) {});
    _keepaliveTimer = Timer.periodic(_keepaliveInterval, (_) {
      final last = _lastPosition;
      final lastAt = _state.lastFixAt;
      if (last == null || lastAt == null) return;
      // Provider-loss guard: if no real fix has arrived in two keepalive
      // intervals, stop fabricating coverage from the stale position. The
      // UI surfaces the growing fix age; matching treats the hole via the
      // interior-gap rule in GpsTrackMatcher.
      if (DateTime.now().toUtc().difference(lastAt) > _keepaliveInterval * 2) {
        return;
      }
      // Re-record the last known position with a fresh timestamp so a
      // moored boat still produces continuous track coverage.
      _record(last, timestampOverride: DateTime.now().toUtc());
    });
    _checkpointTimer = Timer.periodic(_checkpointInterval, (_) {
      final id = _state.trackId;
      if (id != null) unawaited(_repository.checkpoint(id));
    });
  }

  Future<void> stop() async {
    final trackId = _state.trackId;
    await _subscription?.cancel();
    _keepaliveTimer?.cancel();
    _checkpointTimer?.cancel();
    _subscription = null;
    _keepaliveTimer = null;
    _checkpointTimer = null;
    _lastPosition = null;
    if (trackId != null) {
      await _repository.finalizeTrack(trackId);
      await _onTrackFinalized?.call(trackId);
    }
    _setState(const GpsRecorderState());
  }

  Future<void> _onPosition(Position position) async {
    if (position.accuracy > maxAccuracyMeters) return;
    _lastPosition = position;
    await _record(position);
  }

  Future<void> _record(Position position, {DateTime? timestampOverride}) async {
    final trackId = _state.trackId;
    if (trackId == null) return;
    final timestamp = timestampOverride ?? position.timestamp;
    await _repository.appendBufferPoint(
      trackId,
      GpsTrackPoint(
        timestamp: toWallClockEpochSeconds(timestamp),
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      ),
    );
    // The session may have stopped while the append was in flight.
    if (_state.trackId != trackId) return;
    _setState(
      GpsRecorderState(
        status: GpsRecorderStatus.recording,
        trackId: trackId,
        pointCount: _state.pointCount + 1,
        startedAt: _state.startedAt,
        lastFixAt: timestamp,
        lastFixAccuracy: position.accuracy,
      ),
    );
  }

  LocationSettings _buildSettings(String title, String text) {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: title,
          notificationText: text,
          enableWakeLock: true,
        ),
      );
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilterMeters,
    );
  }

  void _setState(GpsRecorderState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }
}
