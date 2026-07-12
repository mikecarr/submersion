import 'package:flutter/material.dart';

import 'package:submersion/features/dive_3d/domain/tissue/tissue_surface_builder.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Explains how to read the tissue landscape: what height/color mean, the
/// M-value danger line, the two horizontal axes, and the depth curve. Kept
/// compact and always visible so the scene is interpretable at a glance.
class TissueLegend extends StatelessWidget {
  final TissueColorMode colorMode;

  const TissueLegend({super.key, required this.colorMode});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.labelSmall;
    final isM = colorMode == TissueColorMode.mValue;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isM) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _ColorScaleBar(),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      context.l10n.dive3d_tissue_legendHeight,
                      style: text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 14,
                    height: 3,
                    color: const Color(0xFFEF4444),
                  ),
                  const SizedBox(width: 6),
                  Text(context.l10n.dive3d_tissue_legendLimit, style: text),
                ],
              ),
              const SizedBox(height: 4),
            ],
            Text(context.l10n.dive3d_tissue_legendAxes, style: text),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 14, height: 3, color: const Color(0xFF38BDF8)),
                const SizedBox(width: 6),
                Text(context.l10n.dive3d_tissue_legendDepth, style: text),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The green -> amber -> red %M-value color scale with 0 / 100% ticks.
class _ColorScaleBar extends StatelessWidget {
  const _ColorScaleBar();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 90,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(
              colors: [Color(0xFF22C55E), Color(0xFFEAB308), Color(0xFFEF4444)],
              stops: [0.0, 0.7, 1.0],
            ),
          ),
        ),
        SizedBox(
          width: 90,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0', style: Theme.of(context).textTheme.labelSmall),
              Text('100%', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ],
    );
  }
}
