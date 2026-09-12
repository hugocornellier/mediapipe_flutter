/// Internal, opt-in instrumentation for the synchronous pipeline benchmark.
///
/// Production calls do not construct this object or run a stopwatch. These are
/// wall-clock stages of the C API wrapper, not GPU kernel or graph-node timings.
final class NativeFrameTimings {
  final _clock = Stopwatch();

  /// Wall time since the previous mark, for the most recent frame.
  final microseconds = <String, int>{};
  int _previous = 0;

  /// Starts a new frame, discarding earlier samples.
  void start() {
    microseconds.clear();
    _previous = 0;
    _clock
      ..reset()
      ..start();
  }

  /// Records the stage that has just finished.
  void mark(String stage) {
    final now = _clock.elapsedMicroseconds;
    microseconds[stage] = now - _previous;
    _previous = now;
  }
}
