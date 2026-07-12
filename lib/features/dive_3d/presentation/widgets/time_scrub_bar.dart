import 'package:flutter/material.dart';

/// Scrubber + play/pause. Owns no state: the page owns the ValueNotifier
/// and the AnimationController so viewport, readout, and bar all observe
/// the same normalized position.
class TimeScrubBar extends StatelessWidget {
  final ValueNotifier<double> position;
  final bool playing;
  final VoidCallback onPlayPause;

  /// Called when the user begins dragging the slider, so the owner can pause
  /// playback -- otherwise the AnimationController keeps overwriting
  /// [position] and fights the drag.
  final VoidCallback? onScrubStart;

  const TimeScrubBar({
    super.key,
    required this.position,
    required this.playing,
    required this.onPlayPause,
    this.onScrubStart,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          onPressed: onPlayPause,
        ),
        Expanded(
          child: ValueListenableBuilder<double>(
            valueListenable: position,
            builder: (context, value, _) => Slider(
              value: value.clamp(0.0, 1.0),
              onChangeStart: onScrubStart == null
                  ? null
                  : (_) => onScrubStart!(),
              onChanged: (v) => position.value = v,
            ),
          ),
        ),
      ],
    );
  }
}
