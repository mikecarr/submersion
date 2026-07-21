import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/media_store/data/quality_presets.dart';
import 'package:submersion/features/media_store/domain/media_upload_quality.dart';

void main() {
  test('original has no preset', () {
    expect(photoPresetFor(MediaUploadQuality.original), isNull);
    expect(videoPresetFor(MediaUploadQuality.original), isNull);
  });

  test('photo presets shrink with level', () {
    expect(photoPresetFor(MediaUploadQuality.high)!.maxDimension, 3072);
    expect(photoPresetFor(MediaUploadQuality.balanced)!.maxDimension, 2048);
    expect(photoPresetFor(MediaUploadQuality.small)!.maxDimension, 1280);
    expect(photoPresetFor(MediaUploadQuality.small)!.jpegQuality, 75);
  });

  test('enum round-trips through name', () {
    expect(
      MediaUploadQuality.values.byName('balanced'),
      MediaUploadQuality.balanced,
    );
  });
}
