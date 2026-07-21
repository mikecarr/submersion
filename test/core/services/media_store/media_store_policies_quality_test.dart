import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:submersion/core/services/media_store/media_store_policies.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media_store/domain/media_upload_quality.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to original for both media types', () async {
    final p = MediaStorePolicies(prefs: await SharedPreferences.getInstance());
    expect(await p.photoUploadQuality(), MediaUploadQuality.original);
    expect(await p.qualityFor(MediaType.video), MediaUploadQuality.original);
  });

  test('round-trips a set photo level', () async {
    final p = MediaStorePolicies(prefs: await SharedPreferences.getInstance());
    await p.setPhotoUploadQuality(MediaUploadQuality.small);
    expect(await p.photoUploadQuality(), MediaUploadQuality.small);
    expect(await p.qualityFor(MediaType.photo), MediaUploadQuality.small);
  });

  test('video level is independent of photo level', () async {
    final p = MediaStorePolicies(prefs: await SharedPreferences.getInstance());
    await p.setPhotoUploadQuality(MediaUploadQuality.high);
    await p.setVideoUploadQuality(MediaUploadQuality.small);
    expect(await p.qualityFor(MediaType.photo), MediaUploadQuality.high);
    expect(await p.qualityFor(MediaType.video), MediaUploadQuality.small);
  });

  test('an unknown stored value falls back to original', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(MediaStorePolicies.photoQualityKey, 'bogus');
    final p = MediaStorePolicies(prefs: prefs);
    expect(await p.photoUploadQuality(), MediaUploadQuality.original);
  });
}
