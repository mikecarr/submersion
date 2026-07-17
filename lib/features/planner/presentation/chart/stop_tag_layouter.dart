import 'dart:ui';

/// Greedy collision-avoiding placement for stop tags. Each tag prefers to sit
/// just right of and below its anchor (the start of a deco shelf); when that
/// spot is taken it slides down, and if it runs out of room below it flips
/// above the anchor. Deterministic and O(n^2), which is fine for the tag
/// counts a dive plan produces.
class StopTagLayouter {
  static List<Rect> layout({
    required List<Offset> anchors,
    required List<Size> sizes,
    required Rect bounds,
    double gap = 2,
  }) {
    assert(anchors.length == sizes.length);
    final placed = <Rect>[];
    for (var i = 0; i < anchors.length; i++) {
      final anchor = anchors[i];
      final size = sizes[i];
      var rect = Rect.fromLTWH(
        anchor.dx + 6,
        anchor.dy + 4,
        size.width,
        size.height,
      );
      if (rect.right > bounds.right) {
        rect = rect.translate(bounds.right - rect.right, 0);
      }
      if (rect.left < bounds.left) {
        rect = rect.translate(bounds.left - rect.left, 0);
      }
      var candidate = rect;
      var guard = 0;
      while (_collides(candidate, placed, gap) && guard++ < 64) {
        candidate = candidate.translate(0, size.height + gap);
        if (candidate.bottom > bounds.bottom) {
          // Out of room below: flip above the anchor and walk upward.
          candidate = Rect.fromLTWH(
            rect.left,
            anchor.dy - 4 - size.height,
            size.width,
            size.height,
          );
          while (_collides(candidate, placed, gap) && guard++ < 64) {
            candidate = candidate.translate(0, -(size.height + gap));
          }
          break;
        }
      }
      placed.add(candidate);
    }
    return placed;
  }

  static bool _collides(Rect rect, List<Rect> placed, double gap) =>
      placed.any((p) => p.inflate(gap / 2).overlaps(rect.inflate(gap / 2)));
}
