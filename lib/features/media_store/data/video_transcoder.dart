import 'dart:io';

import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media_store/data/media_compressor.dart';
import 'package:submersion/features/media_store/domain/media_upload_quality.dart';

/// Video transcoding seam. Phase A ships the interface only; with no
/// implementation registered, the pipeline falls back to uploading the
/// original for a non-Original video level. Phase B provides the
/// ffmpeg-backed implementation (submersion_transcoder plugin).
abstract class VideoTranscoder {
  Future<CompressionResult?> transcode(
    MediaItem item,
    File source,
    MediaUploadQuality level,
  );
}
