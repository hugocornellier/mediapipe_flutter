import 'dart:math' as math;

/// Common frame rates, the nearest of which a measured rate within 2% of it
/// is taken to be.
const _standardRates = [
  24000 / 1001,
  24.0,
  25.0,
  30000 / 1001,
  30.0,
  48.0,
  50.0,
  60000 / 1001,
  60.0,
  90.0,
  100.0,
  120.0,
];

/// How long one frame shows, from the browser's frame callbacks during a
/// moment of muted playback: each callback's media time and its count of
/// frames presented so far. Rounded to a common rate when it is one; null
/// when the callbacks cannot tell.
///
/// A loaded browser drops frames it never presents, so the presented count
/// can fall short of the frames the media time covered: one drop in a dozen
/// callbacks measures a 30 fps file at 27.5, and stepping through the file
/// at that rate skips one frame in twelve. Each callback's step is one frame
/// long except across a drop, so the median step counts the frames the whole
/// span covered. The span, not the shortest step, then gives the rate:
/// browsers report media time with a display frame's jitter, and a step that
/// comes out short would visit every frame twice.
double? frameSecondsFrom(List<(double, int)> callbacks) {
  if (callbacks.length < 2) return null;
  final steps = <double>[];
  for (var i = 1; i < callbacks.length; i++) {
    final (time, presented) = callbacks[i];
    final (previousTime, previousPresented) = callbacks[i - 1];
    if (presented > previousPresented && time > previousTime) {
      steps.add((time - previousTime) / (presented - previousPresented));
    }
  }
  final (firstTime, firstPresented) = callbacks.first;
  final (lastTime, lastPresented) = callbacks.last;
  final span = lastTime - firstTime;
  if (steps.isEmpty || span <= 0) return null;
  steps.sort();
  final step = steps[steps.length ~/ 2];
  final frames = math.max(
    lastPresented - firstPresented,
    (span / step).round(),
  );
  return _rounded(frames / span);
}

/// One frame's length at [rate], rounded to a common rate when it is one.
double _rounded(double rate) {
  // The nearest, since 30000/1001 and 30 lie within 2% of each other.
  final standard = _standardRates.reduce(
    (a, b) => (rate / a - 1).abs() <= (rate / b - 1).abs() ? a : b,
  );
  return (rate / standard - 1).abs() < 0.02 ? 1 / standard : 1 / rate;
}

/// A shorter frame length than the one measured, from a seek to [probe],
/// three quarters into the first frame as measured, which starts at [first]:
/// [presented] is the start of the frame shown there. Null when the probe
/// shows the first frame again, so the measured length stands, or when
/// [presented] is the seek position itself, which Firefox reports and which
/// says nothing about the frame.
///
/// Playback can present every other frame and drop none: a macOS CI runner's
/// Chromium did, so [frameSecondsFrom] read the 30 fps sample as 15 and the
/// reader stepped over every other frame. A frame starting between [first]
/// and the probe gives a length of its start's distance from [first], or a
/// multiple of it, which another probe then shortens.
double? shorterFrameSecondsFrom({
  required double first,
  required double probe,
  required double presented,
}) {
  const margin = 0.001;
  if (presented <= first + margin || presented >= probe - margin) return null;
  return _rounded(1 / (presented - first));
}
