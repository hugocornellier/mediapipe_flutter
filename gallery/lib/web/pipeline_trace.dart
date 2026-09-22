import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Per-frame timings of the live browser pipeline, for the benchmark in
/// `packages/mediapipe-task-vision/tool/benchmarks/2026-09-22-web-live-pipeline/`.
///
/// Off unless the page URL carries `pipeline-trace`. When on, the page exposes
/// `__pipelineTrace()`, which returns the frames recorded since the last call
/// as JSON and clears them. Times are `performance.now()` milliseconds.
abstract final class PipelineTrace {
  static final bool enabled = _install();
  static final _frames = <PipelineFrame>[];

  static double now() => web.window.performance.now();

  static void add(PipelineFrame frame) => _frames.add(frame);

  static bool _install() {
    if (!Uri.base.queryParameters.containsKey('pipeline-trace')) return false;
    globalContext['__pipelineTrace'] = (() {
      final json = jsonEncode([for (final frame in _frames) frame.toJson()]);
      _frames.clear();
      return json.toJS;
    }).toJS;
    return true;
  }
}

/// One processed camera frame. [arrived] is when the browser handed the page
/// the frame; [captured] is the camera's capture time where the browser
/// reports one. [frame] is the start (vsync) of the Flutter frame that
/// painted the result and [built] the end of that frame's task: rendering
/// and every post-frame callback included.
class PipelineFrame {
  PipelineFrame(this.timestamp, this.delegate, this.arrived, this.captured);
  final int timestamp;
  final String delegate;
  final double arrived;
  final double? captured;
  double started = 0, bitmap = 0, detected = 0, frame = 0, built = 0;
  double painted = 0;
  int faces = -1;

  Map<String, Object?> toJson() => {
    'timestamp': timestamp,
    'delegate': delegate,
    'faces': faces,
    'captured': captured,
    'arrived': arrived,
    'started': started,
    'bitmap': bitmap,
    'detected': detected,
    'frame': frame,
    'built': built,
    'painted': painted,
  };
}
