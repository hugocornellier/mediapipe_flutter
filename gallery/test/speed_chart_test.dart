import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_gallery/live/speed_history.dart';
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
}
