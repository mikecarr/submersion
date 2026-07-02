import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:submersion/core/constants/map_style.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_log/data/repositories/dive_repository_impl.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart'
    as domain;
import 'package:submersion/features/dive_log/presentation/providers/dive_providers.dart';
import 'package:submersion/features/dive_log/presentation/widgets/combine_dives_dialog.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

/// Builds a bare-bones dive at [entry] with a [runtimeMin]-minute runtime.
/// Mirrors the `dive()` helper from dive_merge_builder_test.dart.
domain.Dive diveAt(
  String id,
  DateTime entry, {
  int runtimeMin = 30,
  String? diverId = 'diver1',
}) => domain.Dive(
  id: id,
  diverId: diverId,
  dateTime: entry,
  entryTime: entry,
  runtime: Duration(minutes: runtimeMin),
);

/// Fake [DiveRepository] whose `getDivesByIds` returns canned dives.
class _FakeDiveRepository implements DiveRepository {
  _FakeDiveRepository(this.dives);
  final List<domain.Dive> dives;

  @override
  Future<List<domain.Dive>> getDivesByIds(List<String> ids) async => dives;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Minimal SettingsNotifier override that returns default AppSettings.
class _FakeSettingsNotifier extends StateNotifier<AppSettings>
    implements SettingsNotifier {
  _FakeSettingsNotifier() : super(const AppSettings());

  @override
  Future<void> setMapStyle(MapStyle style) async =>
      state = state.copyWith(mapStyle: style);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Pumps a [MaterialApp] + [ProviderScope] (with l10n delegates wired) and
/// opens the [CombineDivesDialog] via [showCombineDivesDialog].
Future<void> pumpCombineDialog(
  WidgetTester tester, {
  required List<domain.Dive> dives,
}) async {
  tester.view.physicalSize = const Size(1024, 768);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  late BuildContext savedContext;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        diveRepositoryProvider.overrideWithValue(_FakeDiveRepository(dives)),
        settingsProvider.overrideWith((ref) => _FakeSettingsNotifier()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              savedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  showCombineDivesDialog(
    context: savedContext,
    diveIds: dives.map((d) => d.id).toList(),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sequential selection shows preview and confirm button', (
    tester,
  ) async {
    await pumpCombineDialog(
      tester,
      dives: [
        diveAt('a', DateTime.utc(2026, 7, 1, 9)),
        diveAt('b', DateTime.utc(2026, 7, 1, 10)),
      ],
    );
    expect(find.text('Combine dives'), findsOneWidget);
    expect(find.textContaining('Surface interval'), findsOneWidget);
    expect(find.text('Combine into one dive'), findsOneWidget);
  });

  testWidgets('overlapping selection shows the explanation panel', (
    tester,
  ) async {
    await pumpCombineDialog(
      tester,
      dives: [
        diveAt('a', DateTime.utc(2026, 7, 1, 9), runtimeMin: 90),
        diveAt('b', DateTime.utc(2026, 7, 1, 10)),
      ],
    );
    expect(find.text('These dives overlap in time'), findsOneWidget);
    expect(find.text('Combine into one dive'), findsNothing);
    // 2 dives selected -> hint at the existing per-dive merge action.
    expect(find.textContaining('Merge with another dive'), findsOneWidget);
  });
}
