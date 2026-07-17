import 'package:flutter/material.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_planner/presentation/providers/dive_planner_providers.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Ascent and descent rate controls for the Setup accordion (Subsurface
/// parity G7/G8). Rates are stored in m/min internally; the sliders label in
/// m/min. Per-depth-band ascent rates land in a later phase.
class PlanRatesSection extends ConsumerWidget {
  const PlanRatesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(divePlanNotifierProvider);
    final notifier = ref.read(divePlanNotifierProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RateSlider(
          label: context.l10n.plannerCanvas_rates_ascent,
          value: state.ascentRate,
          onChanged: (v) => notifier.updateRates(ascent: v),
        ),
        _RateSlider(
          label: context.l10n.plannerCanvas_rates_descent,
          value: state.descentRate,
          onChanged: (v) => notifier.updateRates(descent: v),
        ),
      ],
    );
  }
}

class _RateSlider extends StatelessWidget {
  const _RateSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.labelMedium)),
            Text('${value.round()} m/min', style: theme.textTheme.bodyMedium),
          ],
        ),
        Slider(
          value: value.clamp(1, 30),
          min: 1,
          max: 30,
          divisions: 29,
          label: '${value.round()} m/min',
          onChanged: onChanged,
        ),
      ],
    );
  }
}
