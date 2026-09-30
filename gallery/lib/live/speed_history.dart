import 'package:mediapipe_vision/mediapipe_vision.dart' show VisionDelegate;

/// One frame's inference time, [seconds] into its delegate's run.
typedef SpeedSample = ({double seconds, double milliseconds});

/// Every frame's inference time since the camera started, one series per
/// delegate, for the Stats chart.
///
/// A page runs one delegate at a time. Each series' x is the time its own
/// delegate has been running, so after a switch the other line starts at zero
/// and the two overlay for comparison, without running both at once.
final class SpeedHistory {
  final _series = <VisionDelegate, List<SpeedSample>>{};
  final _chartSeries = <VisionDelegate, List<SpeedSample>>{};
  final _running = <VisionDelegate, double>{};
  final _chartCount = <VisionDelegate, int>{};
  VisionDelegate? _last;
  Duration? _lastAt;
  double _durationSeconds = 0;

  /// The chart averages within fixed quarter-second intervals. Once the
  /// next interval begins, earlier chart points never change.
  static const _chartInterval = 0.25;

  /// The longest pause that still counts as running, as between frames.
  /// A task restart or the still image mode takes longer and adds no time.
  static const _longestGap = 1.0;

  /// The samples of [delegate], oldest first.
  List<SpeedSample> operator [](VisionDelegate delegate) =>
      _series[delegate] ?? const [];

  List<SpeedSample> chartSamples(VisionDelegate delegate) =>
      _chartSeries[delegate] ?? const [];

  double get durationSeconds => _durationSeconds;

  /// The highest value actually drawn for [delegates].
  double chartPeak(Iterable<VisionDelegate> delegates) {
    var peak = 0.0;
    for (final delegate in delegates) {
      for (final sample in chartSamples(delegate)) {
        if (sample.milliseconds > peak) peak = sample.milliseconds;
      }
    }
    return peak;
  }

  /// Samples recorded on every delegate, for repainting when it changes.
  int get length => _series.values.fold(0, (sum, list) => sum + list.length);

  /// Records a frame that took [milliseconds], processed at [at] on any clock
  /// that only moves forward.
  void add(VisionDelegate delegate, double milliseconds, Duration at) {
    var seconds = _running[delegate] ?? 0;
    var continuous = false;
    if (_last == delegate && _lastAt != null) {
      final gap =
          (at - _lastAt!).inMicroseconds / Duration.microsecondsPerSecond;
      if (gap > 0 && gap <= _longestGap) {
        seconds += gap;
        continuous = true;
      }
    }
    _running[delegate] = seconds;
    (_series[delegate] ??= []).add((
      seconds: seconds,
      milliseconds: milliseconds,
    ));
    if (seconds > _durationSeconds) _durationSeconds = seconds;
    final chart = _chartSeries[delegate] ??= [];
    final bucket = (seconds / _chartInterval).floor();
    if (continuous &&
        chart.isNotEmpty &&
        (chart.last.seconds / _chartInterval).floor() == bucket) {
      final count = _chartCount[delegate]!;
      chart[chart.length - 1] = (
        seconds: bucket * _chartInterval,
        milliseconds:
            (chart.last.milliseconds * count + milliseconds) / (count + 1),
      );
      _chartCount[delegate] = count + 1;
    } else {
      chart.add((seconds: bucket * _chartInterval, milliseconds: milliseconds));
      _chartCount[delegate] = 1;
    }
    _last = delegate;
    _lastAt = at;
  }

  /// The mean inference time of [delegate]'s last [frames] frames, or null
  /// before its first.
  double? recent(VisionDelegate delegate, {int frames = 30}) {
    final samples = this[delegate];
    if (samples.isEmpty) return null;
    final window = samples.length < frames
        ? samples
        : samples.sublist(samples.length - frames);
    return window.fold<double>(0, (sum, s) => sum + s.milliseconds) /
        window.length;
  }
}
