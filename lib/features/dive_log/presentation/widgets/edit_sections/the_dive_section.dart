import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:submersion/l10n/l10n_extension.dart';
import 'package:submersion/shared/widgets/forms/form_row.dart';
import 'package:submersion/shared/widgets/forms/form_section.dart';
import 'package:submersion/shared/widgets/forms/stat_strip.dart';

/// A profile-derived value offered on a hero stat cell.
class ProfileSuggestion {
  const ProfileSuggestion({required this.value, required this.onUse});

  /// Already formatted in the diver's units (e.g. "28.6").
  final String value;
  final VoidCallback onUse;
}

/// Group 1 of the dive form: always expanded, owns the core facts.
/// Hero: max depth / bottom time / avg depth. Rows: dive number, entry,
/// exit, surface interval, runtime, site, profile.
class TheDiveSection extends StatelessWidget {
  const TheDiveSection({
    super.key,
    required this.depthSymbol,
    required this.maxDepthController,
    required this.avgDepthController,
    required this.bottomTimeController,
    required this.runtimeController,
    required this.diveNumberController,
    required this.entryText,
    required this.onEditEntry,
    required this.exitText,
    required this.onEditExit,
    required this.siteName,
    required this.onPickSite,
    this.onClearSite,
    this.maxDepthSuggestion,
    this.avgDepthSuggestion,
    this.bottomTimeSuggestion,
    this.runtimeSuggestion,
    this.surfaceIntervalRow,
    this.siteExtras,
    this.profileChild,
  });

  final String depthSymbol;
  final TextEditingController maxDepthController;
  final TextEditingController avgDepthController;
  final TextEditingController bottomTimeController;
  final TextEditingController runtimeController;
  final TextEditingController diveNumberController;
  final String entryText;
  final VoidCallback onEditEntry;
  final String? exitText;
  final VoidCallback onEditExit;
  final String? siteName;
  final VoidCallback onPickSite;
  final VoidCallback? onClearSite;
  final ProfileSuggestion? maxDepthSuggestion;
  final ProfileSuggestion? avgDepthSuggestion;
  final ProfileSuggestion? bottomTimeSuggestion;
  final ProfileSuggestion? runtimeSuggestion;

  /// Surface interval display row (provider-backed), when editing.
  final Widget? surfaceIntervalRow;

  /// Location status, selected-site caption and photo-GPS banner from the
  /// old site section.
  final Widget? siteExtras;

  /// Existing profile block (points count, outlier chip, edit/draw
  /// buttons), stripped of its Card wrapper.
  final Widget? profileChild;

  StatCell _cell(
    String label,
    String? unit,
    TextEditingController controller,
    ProfileSuggestion? suggestion, {
    TextInputType? keyboardType,
  }) {
    return StatCell(
      label: label,
      unit: unit,
      controller: controller,
      profileValue: suggestion?.value,
      onUseProfileValue: suggestion == null ? null : (_) => suggestion.onUse(),
      keyboardType:
          keyboardType ?? const TextInputType.numberWithOptions(decimal: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FormSection(
      label: l10n.diveLog_edit_group_theDive,
      expanded: true,
      onToggle: null,
      hero: StatStrip(
        cells: [
          _cell(
            l10n.diveLog_edit_label_maxDepth,
            depthSymbol,
            maxDepthController,
            maxDepthSuggestion,
          ),
          _cell(
            l10n.diveLog_edit_label_bottomTime,
            'min',
            bottomTimeController,
            bottomTimeSuggestion,
            // Whole minutes; parsed with int.parse on save.
            keyboardType: TextInputType.number,
          ),
          _cell(
            l10n.diveLog_edit_label_avgDepth,
            depthSymbol,
            avgDepthController,
            avgDepthSuggestion,
          ),
        ],
      ),
      children: [
        FormRow.text(
          label: l10n.diveLog_edit_label_diveNumber,
          controller: diveNumberController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          placeholder: l10n.diveLog_edit_row_notSet,
        ),
        FormRow.picker(
          label: l10n.diveLog_edit_row_entry,
          value: entryText,
          onTap: onEditEntry,
        ),
        FormRow.picker(
          label: l10n.diveLog_edit_row_exit,
          value: exitText,
          placeholder: l10n.diveLog_edit_row_notSet,
          onTap: onEditExit,
        ),
        ?surfaceIntervalRow,
        FormRow.text(
          label: l10n.diveLog_edit_label_runtime,
          controller: runtimeController,
          suffixText: 'min',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          placeholder: l10n.diveLog_edit_row_notSet,
        ),
        FormRow.picker(
          label: l10n.diveLog_edit_row_site,
          value: siteName,
          placeholder: l10n.diveLog_edit_row_addSite,
          onTap: onPickSite,
          onClear: siteName == null ? null : onClearSite,
        ),
        ?siteExtras,
        ?profileChild,
      ],
    );
  }
}
