import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/pre_dive/data/repositories/pre_dive_session_repository.dart';
import 'package:submersion/features/pre_dive/domain/entities/pre_dive_session.dart';
import 'package:submersion/features/pre_dive/presentation/pages/pre_dive_session_runner_page.dart';
import 'package:submersion/features/pre_dive/presentation/providers/pre_dive_providers.dart';

import '../../../../helpers/test_app.dart';

/// Records updateItemState calls; every other member is unused by the page
/// under these overrides (providers are overridden separately).
class _FakeSessionRepo implements PreDiveSessionRepository {
  final calls = <({String itemId, PreDiveItemState state})>[];

  @override
  Future<void> updateItemState({
    required String sessionId,
    required String itemId,
    required PreDiveItemState state,
    double? valueNumber,
    String? valueText,
    String? note,
  }) async {
    calls.add((itemId: itemId, state: state));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  PreDiveSession session({
    bool strict = true,
    PreDiveSessionStatus status = PreDiveSessionStatus.inProgress,
  }) => PreDiveSession(
    id: 's1',
    templateName: 'CCR Build',
    strictOrder: strict,
    startedAt: now,
    status: status,
    createdAt: now,
    updatedAt: now,
  );

  PreDiveSessionItem item(
    int order, {
    PreDiveItemState state = PreDiveItemState.pending,
    bool required = true,
  }) => PreDiveSessionItem(
    id: 'i$order',
    sessionId: 's1',
    title: 'Item $order',
    sortOrder: order,
    state: state,
    isRequired: required,
    completedAt: state == PreDiveItemState.pending ? null : now,
    createdAt: now,
    updatedAt: now,
  );

  Future<_FakeSessionRepo> pumpRunner(
    WidgetTester tester, {
    required PreDiveSession s,
    required List<PreDiveSessionItem> items,
  }) async {
    final repo = _FakeSessionRepo();
    await tester.pumpWidget(
      testApp(
        overrides: [
          preDiveSessionRepositoryProvider.overrideWithValue(repo),
          preDiveSessionProvider('s1').overrideWith((ref) async => s),
          preDiveSessionItemsProvider('s1').overrideWith((ref) async => items),
        ],
        child: const PreDiveSessionRunnerPage(sessionId: 's1'),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('shows progress and strict-order gating', (tester) async {
    final items = [item(0, state: PreDiveItemState.done), item(1), item(2)];
    final repo = await pumpRunner(tester, s: session(), items: items);

    expect(find.text('1 of 3'), findsOneWidget);

    // Second item is the next actionable; third is inert.
    final tile1 = tester.widget<ListTile>(
      find.ancestor(of: find.text('Item 1'), matching: find.byType(ListTile)),
    );
    final tile2 = tester.widget<ListTile>(
      find.ancestor(of: find.text('Item 2'), matching: find.byType(ListTile)),
    );
    expect(tile1.enabled, isTrue);
    expect(tile2.enabled, isFalse);

    // Tapping the actionable item records a done state change.
    await tester.tap(find.text('Item 1'));
    await tester.pumpAndSettle();
    expect(repo.calls.single.itemId, 'i1');
    expect(repo.calls.single.state, PreDiveItemState.done);
  });

  // Note: one pump per test — re-pumping a new ProviderScope in the same
  // test updates the existing scope element, whose overrides are fixed at
  // creation, so the second set of overrides would be silently ignored.
  testWidgets('Complete disabled while a required item pends', (tester) async {
    await pumpRunner(tester, s: session(), items: [item(0)]);
    final disabled = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Complete'),
    );
    expect(disabled.onPressed, isNull);
  });

  testWidgets('Complete enabled once required items resolve', (tester) async {
    await pumpRunner(
      tester,
      s: session(),
      items: [item(0, state: PreDiveItemState.done)],
    );
    final enabled = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Complete'),
    );
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('locked session renders banner and no Complete button', (
    tester,
  ) async {
    await pumpRunner(
      tester,
      s: session(status: PreDiveSessionStatus.completed),
      items: [item(0, state: PreDiveItemState.done)],
    );
    expect(find.textContaining('This checklist is locked'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Complete'), findsNothing);
    // No abort action either.
    expect(find.byIcon(Icons.close), findsNothing);
  });
}
