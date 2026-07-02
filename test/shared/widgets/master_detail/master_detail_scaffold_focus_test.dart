import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';
import 'package:submersion/shared/widgets/master_detail/master_detail_scaffold.dart';

/// Builds a [MasterDetailScaffold] inside a router at [initialLocation] so
/// query params (`?selected=1&mode=edit`) drive the detail pane mode.
///
/// The desktop (master-detail) layout requires width >= 800.
Widget _buildScaffold({
  required String initialLocation,
  required Widget Function(
    BuildContext context,
    void Function(String?) onItemSelected,
    String? selectedId,
  )
  masterBuilder,
  required Widget Function(
    BuildContext context,
    String itemId,
    void Function(String savedId) onSaved,
    VoidCallback onCancel,
  )
  editBuilder,
  double width = 1200,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/test',
        builder: (context, state) => MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: MasterDetailScaffold(
            sectionId: 'test',
            masterBuilder: masterBuilder,
            detailBuilder: (_, id) => Text('Detail $id'),
            summaryBuilder: (_) => const Text('Summary'),
            editBuilder: editBuilder,
            createBuilder: (context, onSaved, onCancel) =>
                editBuilder(context, 'new', onSaved, onCancel),
          ),
        ),
      ),
    ],
  );

  return ProviderScope(
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

/// A minimal traversable widget wrapping an explicit [FocusNode] so tests can
/// assert exactly which pane holds focus.
Widget _focusTarget(FocusNode node) =>
    Focus(focusNode: node, child: const SizedBox(width: 20, height: 20));

void main() {
  group('MasterDetailScaffold focus traversal (issue #444)', () {
    testWidgets(
      'edit mode: Tab from the edit pane never moves focus into the master pane',
      (tester) async {
        final masterNode = FocusNode(debugLabel: 'master');
        final field1 = FocusNode(debugLabel: 'edit-field-1');
        final field2 = FocusNode(debugLabel: 'edit-field-2');
        addTearDown(masterNode.dispose);
        addTearDown(field1.dispose);
        addTearDown(field2.dispose);

        await tester.pumpWidget(
          _buildScaffold(
            initialLocation: '/test?selected=1&mode=edit',
            masterBuilder: (context, onSelect, selectedId) =>
                _focusTarget(masterNode),
            editBuilder: (context, id, onSaved, onCancel) =>
                Column(children: [_focusTarget(field1), _focusTarget(field2)]),
          ),
        );
        await tester.pumpAndSettle();

        // Start focus on the last field in the edit pane.
        field2.requestFocus();
        await tester.pump();
        expect(field2.hasFocus, isTrue);

        // Tabbing forward from the last edit field must wrap within the edit
        // pane, not cross into the master list on the left.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();

        expect(
          masterNode.hasFocus,
          isFalse,
          reason: 'Tab must not move focus into the master (list) pane.',
        );
        expect(
          field1.hasFocus || field2.hasFocus,
          isTrue,
          reason: 'Focus should remain within the edit pane.',
        );
      },
    );

    testWidgets(
      'create mode: Tab from the create pane never moves focus into the master pane',
      (tester) async {
        final masterNode = FocusNode(debugLabel: 'master');
        final field1 = FocusNode(debugLabel: 'create-field-1');
        final field2 = FocusNode(debugLabel: 'create-field-2');
        addTearDown(masterNode.dispose);
        addTearDown(field1.dispose);
        addTearDown(field2.dispose);

        await tester.pumpWidget(
          _buildScaffold(
            initialLocation: '/test?mode=new',
            masterBuilder: (context, onSelect, selectedId) =>
                _focusTarget(masterNode),
            editBuilder: (context, id, onSaved, onCancel) =>
                Column(children: [_focusTarget(field1), _focusTarget(field2)]),
          ),
        );
        await tester.pumpAndSettle();

        field2.requestFocus();
        await tester.pump();
        expect(field2.hasFocus, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();

        expect(masterNode.hasFocus, isFalse);
        expect(field1.hasFocus || field2.hasFocus, isTrue);
      },
    );
  });
}
