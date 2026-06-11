import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';
import 'package:submersion/shared/widgets/forms/form_section.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('FormSection expanded', () {
    testWidgets('renders label, hero and children', (tester) async {
      await tester.pumpWidget(
        _wrap(
          FormSection(
            label: 'The Dive',
            expanded: true,
            onToggle: () {},
            hero: const Text('HERO'),
            children: const [Text('row one'), Text('row two')],
          ),
        ),
      );
      expect(find.text('THE DIVE'), findsOneWidget);
      expect(find.text('HERO'), findsOneWidget);
      expect(find.text('row one'), findsOneWidget);
      expect(find.text('row two'), findsOneWidget);
    });

    testWidgets('always-expanded section (null onToggle) shows no chevron', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const FormSection(
            label: 'The Dive',
            expanded: true,
            onToggle: null,
            children: [Text('row one')],
          ),
        ),
      );
      expect(find.byIcon(Icons.keyboard_arrow_up), findsNothing);
    });

    testWidgets('collapse chevron calls onToggle', (tester) async {
      var toggled = 0;
      await tester.pumpWidget(
        _wrap(
          FormSection(
            label: 'Conditions',
            expanded: true,
            onToggle: () => toggled++,
            children: const [Text('row one')],
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
      expect(toggled, 1);
    });
  });

  group('FormSection collapsed', () {
    testWidgets('with data shows summary, hides children, tap expands', (
      tester,
    ) async {
      var toggled = 0;
      await tester.pumpWidget(
        _wrap(
          FormSection(
            label: 'Conditions',
            expanded: false,
            onToggle: () => toggled++,
            summary: 'Salt - 24 C - 15 m vis',
            children: const [Text('row one')],
          ),
        ),
      );
      expect(find.text('Salt - 24 C - 15 m vis'), findsOneWidget);
      expect(find.text('row one'), findsNothing);
      await tester.tap(find.text('Salt - 24 C - 15 m vis'));
      expect(toggled, 1);
    });

    testWidgets('empty shows invitation with add affordance', (tester) async {
      await tester.pumpWidget(
        _wrap(
          FormSection(
            label: 'Conditions',
            expanded: false,
            onToggle: () {},
            isEmpty: true,
            emptyInvitation: 'Add conditions',
            children: const [Text('row one')],
          ),
        ),
      );
      expect(find.text('Add conditions'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.text('row one'), findsNothing);
    });

    testWidgets('error badge shows localized issue count', (tester) async {
      await tester.pumpWidget(
        _wrap(
          FormSection(
            label: 'Gas & Gear',
            expanded: false,
            onToggle: () {},
            summary: '2x AL80',
            errorCount: 2,
            children: const [Text('row one')],
          ),
        ),
      );
      expect(find.text('2 issues'), findsOneWidget);
    });

    testWidgets('no badge when errorCount is zero', (tester) async {
      await tester.pumpWidget(
        _wrap(
          FormSection(
            label: 'Gas & Gear',
            expanded: false,
            onToggle: () {},
            summary: '2x AL80',
            children: const [Text('row one')],
          ),
        ),
      );
      expect(find.textContaining('issue'), findsNothing);
    });
  });
}
