import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:submersion/features/safety/domain/services/no_fly_service.dart';
import 'package:submersion/features/safety/presentation/providers/no_fly_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Flying-after-diving status: the DAN/UHMS guideline countdown from the
/// most recent dives. Lives in the Planning section.
class NoFlyPage extends ConsumerStatefulWidget {
  const NoFlyPage({super.key});

  @override
  ConsumerState<NoFlyPage> createState() => _NoFlyPageState();
}

class _NoFlyPageState extends ConsumerState<NoFlyPage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresh the countdown display once a minute while the page is open.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final statusAsync = ref.watch(noFlyStatusProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.safetySettings_noFlyHeader)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [NoFlyStatusCard(status: statusAsync.value)],
      ),
    );
  }
}

/// The no-fly countdown card (also usable on other surfaces).
class NoFlyStatusCard extends StatelessWidget {
  final NoFlyStatus? status;

  const NoFlyStatusCard({required this.status, super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final now = DateTime.now().toUtc();
    final active = status != null && status!.until.isAfter(now);

    if (!active) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.flight_takeoff, color: theme.colorScheme.primary),
          title: Text(l10n.safetyHub_noFly_clear_title),
          subtitle: Text(l10n.safetyHub_noFly_clear_subtitle),
        ),
      );
    }

    final remaining = status!.remaining(now);
    final untilLocal = status!.until.toLocal();
    final untilText = DateFormat.E().add_jm().format(untilLocal);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.airplanemode_inactive,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.safetyHub_noFly_active_title(
                      formatNoFlyRemaining(remaining),
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.safetyHub_noFly_until(untilText),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _categoryText(l10n, status!.category),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.safetyHub_noFly_disclaimer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryText(AppLocalizations l10n, NoFlyCategory category) {
    final hours = status!.interval.inHours;
    return switch (category) {
      NoFlyCategory.single => l10n.safetyHub_noFly_category_single(hours),
      NoFlyCategory.repetitive => l10n.safetyHub_noFly_category_repetitive(
        hours,
      ),
      NoFlyCategory.deco => l10n.safetyHub_noFly_category_deco(hours),
    };
  }
}

/// "14h 20m" style remaining-time label shared with the dashboard banner.
String formatNoFlyRemaining(Duration remaining) {
  final hours = remaining.inHours;
  final minutes = remaining.inMinutes % 60;
  if (hours == 0) return '${minutes}m';
  return '${hours}h ${minutes}m';
}
