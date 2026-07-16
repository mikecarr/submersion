import 'package:flutter/material.dart';

/// Shared visual style for the wizard's clickable selection cards (fork
/// choices, existing-data sources, cloud providers).
///
/// Centralised so every step reads as the same medium-translucent "glass"
/// surface floating over the ocean background, instead of a mix of translucent
/// (start page) and opaque-dark (provider) cards.
class WizardOptionCardStyle {
  const WizardOptionCardStyle._();

  /// Medium-translucent fill: clearly visible over the bright ocean without
  /// the heavy opaque-dark look of a default [Card].
  static Color fill(ThemeData theme) =>
      theme.colorScheme.onSurface.withValues(alpha: 0.1);

  /// Rounded outline with a faint translucent border for definition.
  static ShapeBorder shape(ThemeData theme) => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
    side: BorderSide(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.16),
    ),
  );
}
