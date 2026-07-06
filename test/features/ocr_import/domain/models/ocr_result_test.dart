import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/ocr_import/domain/models/ocr_result.dart';

void main() {
  group('OcrTextBlock', () {
    test('exposes center of bounding box', () {
      const block = OcrTextBlock(
        text: 'DEPTH',
        boundingBox: Rect.fromLTWH(10, 20, 40, 10),
      );
      expect(block.center, const Offset(30, 25));
    });

    test('height reflects bounding box height', () {
      const block = OcrTextBlock(
        text: '69',
        boundingBox: Rect.fromLTWH(0, 0, 20, 14),
      );
      expect(block.height, 14);
    });
  });
}
