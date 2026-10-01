import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_gallery/live/speed_history.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

Duration _ms(int value) => Duration(milliseconds: value);

List<double> _seconds(SpeedHistory history, VisionDelegate delegate) => [
  for (final sample in history[delegate]) sample.seconds,
];

void main() {
  test('each delegate is timed from its own start, so the lines overlay', () {
    final history = SpeedHistory()
      ..add(VisionDelegate.gpu, 5.4, _ms(0))
      ..add(VisionDelegate.gpu, 5.8, _ms(100))
      ..add(VisionDelegate.gpu, 5.6, _ms(200))
      ..add(VisionDelegate.cpu, 8.7, _ms(1400))
      ..add(VisionDelegate.cpu, 8.3, _ms(1500));
    expect(_seconds(history, VisionDelegate.gpu), [
      0,
      closeTo(.1, 1e-9),
      closeTo(.2, 1e-9),
    ]);
    expect(_seconds(history, VisionDelegate.cpu), [0, closeTo(.1, 1e-9)]);
    expect(history[VisionDelegate.cpu].last.milliseconds, 8.3);
    expect(history.length, 5);
  });

  test('switching back continues a delegate where it stopped', () {
    final history = SpeedHistory()
      ..add(VisionDelegate.cpu, 9, _ms(0))
      ..add(VisionDelegate.cpu, 9, _ms(500))
      ..add(VisionDelegate.gpu, 6, _ms(2000))
      ..add(VisionDelegate.cpu, 8, _ms(4000))
      ..add(VisionDelegate.cpu, 8, _ms(4250));
    expect(_seconds(history, VisionDelegate.cpu), [
      0,
      closeTo(.5, 1e-9),
      closeTo(.5, 1e-9),
      closeTo(.75, 1e-9),
    ]);
  });

  test('a pause of over a second adds no running time', () {
    final history = SpeedHistory()
      ..add(VisionDelegate.gpu, 6, _ms(0))
      ..add(VisionDelegate.gpu, 6, _ms(3000))
      ..add(VisionDelegate.gpu, 6, _ms(3200));
    expect(_seconds(history, VisionDelegate.gpu), [0, 0, closeTo(.2, 1e-9)]);
  });

  test('recent averages the latest frames of one delegate', () {
    final history = SpeedHistory();
    expect(history.recent(VisionDelegate.cpu), isNull);
    for (var i = 0; i < 40; i++) {
      history.add(VisionDelegate.cpu, i < 10 ? 100 : 8, _ms(i * 30));
    }
    expect(history.recent(VisionDelegate.cpu), 8);
    expect(history.recent(VisionDelegate.cpu, frames: 40), closeTo(31, 1e-9));
  });

  test('the vertical peak follows the values actually drawn', () {
    final history = SpeedHistory()
      ..add(VisionDelegate.cpu, 20, _ms(0))
      ..add(VisionDelegate.cpu, 10, _ms(100))
      ..add(VisionDelegate.cpu, 8, _ms(300));
    final first = history.chartSamples(VisionDelegate.cpu).first;
    expect(first.milliseconds, 15);
    expect(history.chartPeak([VisionDelegate.cpu]), 15);

    for (var i = 4; i <= 400; i++) {
      history.add(VisionDelegate.cpu, 5, _ms(i * 100));
    }
    expect(history.chartSamples(VisionDelegate.cpu).first, first);
    expect(history.chartPeak([VisionDelegate.cpu]), 15);
    expect(history.durationSeconds, greaterThan(30));
  });

  test('a resumed delegate never rewrites a point from before the pause', () {
    final history = SpeedHistory()
      ..add(VisionDelegate.cpu, 20, _ms(0))
      ..add(VisionDelegate.cpu, 10, _ms(100));
    final before = history.chartSamples(VisionDelegate.cpu).first;
    history.add(VisionDelegate.cpu, 5, _ms(3000));
    expect(history.chartSamples(VisionDelegate.cpu).first, before);
    expect(history.chartSamples(VisionDelegate.cpu).length, 2);
  });

  test('clear forgets every frame, and each line starts again from zero', () {
    final history = SpeedHistory()
      ..add(VisionDelegate.gpu, 5, _ms(0))
      ..add(VisionDelegate.gpu, 6, _ms(100))
      ..add(VisionDelegate.cpu, 9, _ms(1000));
    history.clear();
    expect(history.length, 0);
    expect(history.durationSeconds, 0);
    expect(history.recent(VisionDelegate.gpu), isNull);
    expect(history.chartSamples(VisionDelegate.cpu), isEmpty);
    expect(history.chartPeak(VisionDelegate.values), 0);

    // Even a frame right after the last one starts a fresh line.
    history
      ..add(VisionDelegate.cpu, 8, _ms(1100))
      ..add(VisionDelegate.cpu, 8, _ms(1200));
    expect(_seconds(history, VisionDelegate.cpu), [0, closeTo(.1, 1e-9)]);
    expect(history[VisionDelegate.gpu], isEmpty);
  });
}
