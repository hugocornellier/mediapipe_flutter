import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_gallery/live/speed_history.dart';
import 'package:mediapipe_gallery/ui/components.dart';
import 'package:mediapipe_gallery/ui/design.dart';
import 'package:mediapipe_gallery/ui/speed_chart.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

void main() {
  testWidgets('the CPU and GPU checkboxes control the chart lines', (
    tester,
  ) async {
    final history = SpeedHistory()
      ..add(VisionDelegate.cpu, 10, Duration.zero)
      ..add(VisionDelegate.gpu, 5, const Duration(milliseconds: 100));
    await tester.pumpWidget(
      MaterialApp(
        theme: galleryTheme(Brightness.dark),
        home: Scaffold(
          body: StatsCard(
            history: history,
            delegates: const [VisionDelegate.cpu, VisionDelegate.gpu],
          ),
        ),
      ),
    );

    SpeedChartPainter chart() =>
        tester
                .widget<CustomPaint>(
                  find
                      .descendant(
                        of: find.byType(StatsCard),
                        matching: find.byType(CustomPaint),
                      )
                      .first,
                )
                .painter!
            as SpeedChartPainter;

    expect(chart().shown, [VisionDelegate.cpu, VisionDelegate.gpu]);
    await tester.tap(find.byKey(const ValueKey('stats-gpu')));
    await tester.pump();
    expect(chart().shown, [VisionDelegate.cpu]);
    await tester.tap(find.byKey(const ValueKey('stats-cpu')));
    await tester.pump();
    expect(chart().shown, isEmpty);
    await tester.tap(find.byKey(const ValueKey('stats-gpu')));
    await tester.pump();
    expect(chart().shown, [VisionDelegate.gpu]);
  });

  testWidgets('the switch names the other delegate and asks for it', (
    tester,
  ) async {
    final asked = <VisionDelegate>[];
    for (final (running, label, other) in [
      (VisionDelegate.cpu, 'Switch to GPU', VisionDelegate.gpu),
      (VisionDelegate.gpu, 'Switch to CPU', VisionDelegate.cpu),
    ]) {
      await _pumpCard(
        tester,
        StatsCard(
          history: SpeedHistory(),
          delegates: const [VisionDelegate.cpu, VisionDelegate.gpu],
          delegate: running,
          onSwitchDelegate: asked.add,
        ),
      );
      expect(find.text(label), findsOneWidget);
      await tester.tap(find.text(label));
      expect(asked.last, other);
    }
    expect(asked, [VisionDelegate.gpu, VisionDelegate.cpu]);
  });

  testWidgets('a task with one delegate has nothing to switch to', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      StatsCard(
        history: SpeedHistory(),
        delegates: const [VisionDelegate.cpu],
        delegate: VisionDelegate.cpu,
        onSwitchDelegate: (_) => fail('no other delegate'),
      ),
    );
    expect(find.byKey(const ValueKey('stats-switch')), findsNothing);
  });

  testWidgets('the switch is disabled while the task restarts', (tester) async {
    await _pumpCard(
      tester,
      StatsCard(
        history: SpeedHistory(),
        delegates: const [VisionDelegate.cpu, VisionDelegate.gpu],
        delegate: VisionDelegate.gpu,
      ),
    );
    final button = find.byKey(const ValueKey('stats-switch'));
    expect(button, findsOneWidget);
    expect(tester.widget<OutlineButton>(button).onPressed, isNull);
    // The label merges into the button's own semantics node.
    final node = tester.getSemantics(find.text('Switch to CPU'));
    expect(node.flagsCollection.isEnabled, Tristate.isFalse);
    await tester.tap(button);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset clears the chart', (tester) async {
    final history = SpeedHistory()
      ..add(VisionDelegate.cpu, 10, Duration.zero)
      ..add(VisionDelegate.cpu, 9, const Duration(milliseconds: 100));
    await _pumpCard(
      tester,
      StatefulBuilder(
        builder: (context, setState) => StatsCard(
          history: history,
          delegates: const [VisionDelegate.cpu, VisionDelegate.gpu],
          delegate: VisionDelegate.cpu,
          onSwitchDelegate: (_) {},
          onReset: () => setState(history.clear),
        ),
      ),
    );
    expect(find.text('Waiting for frames'), findsNothing);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(history.length, 0);
    expect(find.text('Waiting for frames'), findsOneWidget);
  });
}

Future<void> _pumpCard(WidgetTester tester, Widget card) => tester.pumpWidget(
  MaterialApp(
    theme: galleryTheme(Brightness.dark),
    home: Scaffold(body: card),
  ),
);
