import 'package:submersion/features/media_store/domain/media_upload_quality.dart';

/// Photo rendition target: a long-edge ceiling and a JPEG quality.
class PhotoQualityPreset {
  const PhotoQualityPreset({
    required this.maxDimension,
    required this.jpegQuality,
  });
  final int maxDimension;
  final int jpegQuality;
}

/// Video rendition target (consumed in Phase B by the ffmpeg transcoder).
class VideoQualityPreset {
  const VideoQualityPreset({
    required this.maxHeight,
    required this.crf,
    required this.audioBitrateKbps,
  });
  final int maxHeight;
  final int crf;
  final int audioBitrateKbps;
}

const Map<MediaUploadQuality, PhotoQualityPreset> _photo = {
  MediaUploadQuality.high: PhotoQualityPreset(
    maxDimension: 3072,
    jpegQuality: 90,
  ),
  MediaUploadQuality.balanced: PhotoQualityPreset(
    maxDimension: 2048,
    jpegQuality: 85,
  ),
  MediaUploadQuality.small: PhotoQualityPreset(
    maxDimension: 1280,
    jpegQuality: 75,
  ),
};

const Map<MediaUploadQuality, VideoQualityPreset> _video = {
  MediaUploadQuality.high: VideoQualityPreset(
    maxHeight: 1080,
    crf: 20,
    audioBitrateKbps: 128,
  ),
  MediaUploadQuality.balanced: VideoQualityPreset(
    maxHeight: 720,
    crf: 23,
    audioBitrateKbps: 128,
  ),
  MediaUploadQuality.small: VideoQualityPreset(
    maxHeight: 480,
    crf: 26,
    audioBitrateKbps: 96,
  ),
};

/// The photo preset for [level], or null for [MediaUploadQuality.original].
PhotoQualityPreset? photoPresetFor(MediaUploadQuality level) => _photo[level];

/// The video preset for [level], or null for [MediaUploadQuality.original].
VideoQualityPreset? videoPresetFor(MediaUploadQuality level) => _video[level];
