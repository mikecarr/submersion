import 'package:shared_preferences/shared_preferences.dart';

import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media_store/domain/media_upload_quality.dart';

/// Device-local transfer policies (design spec section 9). Stored in
/// SharedPreferences like the attach state: policies are per-device
/// choices and must not ride a database restore.
class MediaStorePolicies {
  MediaStorePolicies({SharedPreferences? prefs}) : _prefs = prefs;

  final SharedPreferences? _prefs;

  static const String autoUploadKey = 'media_store_auto_upload';
  static const String photosOnCellularKey = 'media_store_photos_on_cellular';
  static const String videosOnCellularKey = 'media_store_videos_on_cellular';
  static const String photoQualityKey = 'media_store_photo_quality';
  static const String videoQualityKey = 'media_store_video_quality';

  Future<SharedPreferences> get _resolved async =>
      _prefs ?? await SharedPreferences.getInstance();

  Future<bool> autoUpload() async =>
      (await _resolved).getBool(autoUploadKey) ?? true;

  Future<void> setAutoUpload(bool value) async =>
      (await _resolved).setBool(autoUploadKey, value);

  Future<bool> photosOnCellular() async =>
      (await _resolved).getBool(photosOnCellularKey) ?? true;

  Future<void> setPhotosOnCellular(bool value) async =>
      (await _resolved).setBool(photosOnCellularKey, value);

  /// Default false. Phase 2 does not upload videos at all; this ships now
  /// so Phase 3's multipart transfer only has to consume it.
  Future<bool> videosOnCellular() async =>
      (await _resolved).getBool(videosOnCellularKey) ?? false;

  Future<void> setVideosOnCellular(bool value) async =>
      (await _resolved).setBool(videosOnCellularKey, value);

  /// Per-device photo upload quality; defaults to [MediaUploadQuality.original]
  /// so existing users' upload behavior never changes silently.
  Future<MediaUploadQuality> photoUploadQuality() async =>
      _readQuality(photoQualityKey);

  Future<void> setPhotoUploadQuality(MediaUploadQuality value) async =>
      (await _resolved).setString(photoQualityKey, value.name);

  Future<MediaUploadQuality> videoUploadQuality() async =>
      _readQuality(videoQualityKey);

  Future<void> setVideoUploadQuality(MediaUploadQuality value) async =>
      (await _resolved).setString(videoQualityKey, value.name);

  /// The level for [type]'s media (photos vs video).
  Future<MediaUploadQuality> qualityFor(MediaType type) async =>
      type == MediaType.video
      ? await videoUploadQuality()
      : await photoUploadQuality();

  Future<MediaUploadQuality> _readQuality(String key) async {
    final raw = (await _resolved).getString(key);
    if (raw == null) return MediaUploadQuality.original;
    try {
      return MediaUploadQuality.values.byName(raw);
    } on ArgumentError {
      return MediaUploadQuality.original;
    }
  }
}
