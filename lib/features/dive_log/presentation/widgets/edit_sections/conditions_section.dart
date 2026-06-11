import 'package:flutter/material.dart';

import 'package:submersion/l10n/l10n_extension.dart';
import 'package:submersion/shared/widgets/forms/form_section.dart';
import 'package:submersion/shared/widgets/forms/stat_strip.dart';

/// Group 3 of the dive form. Hero: water temp (edit) / visibility (display)
/// / air temp (edit). The dropdown cluster (dive type, water type,
/// entry/exit, current, swell, altitude) and the weather block (fetch
/// button, humidity, wind, pressure, cloud, precipitation, description)
/// move in as page-provided slots.
class ConditionsSection extends StatelessWidget {
  const ConditionsSection({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.summary,
    required this.isEmpty,
    required this.temperatureSymbol,
    required this.waterTempController,
    required this.airTempController,
    required this.visibilityValue,
    required this.environmentChild,
    required this.weatherChild,
    this.errorCount = 0,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final String summary;
  final bool isEmpty;
  final String temperatureSymbol;
  final TextEditingController waterTempController;
  final TextEditingController airTempController;

  /// Display text mirroring the visibility dropdown below.
  final String visibilityValue;
  final Widget environmentChild;
  final Widget weatherChild;
  final int errorCount;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FormSection(
      label: l10n.diveLog_edit_group_conditions,
      expanded: expanded,
      onToggle: onToggle,
      summary: summary,
      isEmpty: isEmpty,
      emptyInvitation: l10n.diveLog_edit_invite_conditions,
      errorCount: errorCount,
      hero: StatStrip(
        cells: [
          StatCell(
            label: l10n.diveLog_edit_label_waterTemp,
            unit: temperatureSymbol,
            controller: waterTempController,
          ),
          StatCell(
            label: l10n.diveLog_edit_label_visibility,
            displayValue: visibilityValue,
          ),
          StatCell(
            label: l10n.diveLog_edit_label_airTemp,
            unit: temperatureSymbol,
            controller: airTempController,
          ),
        ],
      ),
      children: [environmentChild, weatherChild],
    );
  }
}
