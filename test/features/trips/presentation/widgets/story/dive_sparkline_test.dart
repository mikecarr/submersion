import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/trips/presentation/widgets/story/dive_sparkline.dart';

void main() {
  testWidgets('renders a CustomPaint for a real profile', (tester) async {
    final profile = List.generate(
      50,
      (i) => DiveProfilePoint(timestamp: i * 30, depth: (i % 10) + 5.0),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DiveSparkline(profile: profile)),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(DiveSparkline),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders nothing for an empty profile', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DiveSparkline(profile: [])),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(DiveSparkline),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });
}
