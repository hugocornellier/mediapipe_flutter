import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show Random;

import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart';

import '../runner/checks.dart';
import '../runner/native_interface.dart';
import '../types/vision_types.dart';
import 'gpu_frame_budget.dart';

/// Google's native task on its own isolate: the shared checks, then requests
/// in submission order, with the task created, used and closed there.
final class VisionTaskWorker<R> implements NativeTaskRunner<R> {
  VisionTaskWorker._(this._checks) {
    _events.listen(_receive);
  }
  final VisionTaskChecks _checks;
  final int _tag = Random().nextInt(1 << 32);
  final _events = ReceivePort();
  final _ready = Completer<void>();
  final _exited = Completer<void>();
  final _pending = <int, Completer<R?>>{};
  SendPort? _commands;
  var _nextId = 0;
  Future<void>? _disposal;

  /// The task's name, as its errors say it.
  String get name => _checks.name;

  /// Construct the native owner from a top-level factory on a new isolate.
  ///
  /// [reopenAfterBytes] overrides the [GpuFrameBudget] that bounds what
  /// Google's macOS GPU path keeps, so tests can exercise the reopening.
  static Future<VisionTaskWorker<R>> create<R, O extends VisionTaskOptions>(
    O options,
    NativeVisionTask<R> Function(O) factory,
    String name,
    String debugName, {
    int? reopenAfterBytes,
  }) async {
    final worker = VisionTaskWorker<R>._(
      VisionTaskChecks(name, options.runningMode),
    );
    _trace(worker._tag, debugName, 'spawn', 'start');
    try {
      await Isolate.spawn(
        _runWorker<R, O>,
        (
          worker._events.sendPort,
          options,
          factory,
          worker._tag,
          reopenAfterBytes,
        ),
        onError: worker._events.sendPort,
        onExit: worker._events.sendPort,
        debugName: debugName,
      );
    } catch (error, stack) {
      worker._events.close();
      Error.throwWithStackTrace(error, stack);
    }
    await worker._ready.future;
    return worker;
  }

  @override
  Future<R> processImage(
    VisionImage image,
    int rotationDegrees,
    VisionRegionOfInterest? regionOfInterest,
  ) async {
    _checks.image(rotationDegrees);
    return (await _request((image, rotationDegrees, null, regionOfInterest)))!;
  }

  @override
  Future<R> processVideo(
    VisionImage image,
    int rotationDegrees,
    int timestampMilliseconds,
    VisionRegionOfInterest? regionOfInterest,
  ) async {
    _checks.video(rotationDegrees, timestampMilliseconds);
    return (await _request((
      image,
      rotationDegrees,
      timestampMilliseconds,
      regionOfInterest,
    )))!;
  }

  Future<R?> _request(VisionTaskInput? input) {
    final id = _nextId++;
    final completion = Completer<R?>();
    _pending[id] = completion;
    _commands!.send((id, input));
    return completion.future;
  }

  @override
  Future<void> dispose() {
    _checks.markDisposing();
    return _disposal ??= _close();
  }

  Future<void> _close() async {
    try {
      if (_checks.failure == null) await _request(null);
    } finally {
      await _exited.future;
    }
  }

  void _receive(dynamic event) {
    switch (event) {
      case SendPort port:
        _trace(_tag, name, 'spawn', 'end');
        _commands = port;
        _ready.complete();
      case (int id, Object? result, TaskException? error):
        _trace(_tag, name, id, 'received');
        final completion = _pending.remove(id);
        if (error != null) {
          completion?.completeError(error);
        } else {
          completion?.complete(result as R?);
        }
      case TaskException error:
        _fail(error);
      case List<dynamic> error:
        _fail(TaskException('Worker failed: ${error.join('\n')}'));
      case null:
        _trace(_tag, name, 'exit', 'exited');
        if (!_ready.isCompleted || _pending.isNotEmpty || !_checks.disposing) {
          _fail(
            const TaskException('Native vision worker exited unexpectedly.'),
          );
        }
        _events.close();
        _exited.complete();
    }
  }

  void _fail(TaskException error) {
    _checks.failure ??= error;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final completion in _pending.values) {
      completion.completeError(error);
    }
    _pending.clear();
  }
}

Future<void> _runWorker<R, O extends VisionTaskOptions>(
  (SendPort, O, NativeVisionTask<R> Function(O), int, int?) initial,
) async {
  final (parent, options, factory, tag, reopenAfterBytes) = initial;
  final name = Isolate.current.debugName ?? 'worker';
  final commands = ReceivePort();
  final budget = GpuFrameBudget(options, limitBytes: reopenAfterBytes);
  NativeVisionTask<R>? native;
  try {
    _trace(tag, name, 'create', 'start');
    var task = native = factory(options);
    _trace(tag, name, 'create', 'end');
    if (budget.limitBytes != null) _holdModel(options);
    parent.send(commands.sendPort);
    await for (final dynamic message in commands) {
      final (id, input) = message as (int, VisionTaskInput?);
      R? result;
      TaskException? failure;
      _trace(tag, name, id, 'start');
      try {
        if (input == null) {
          task.close();
        } else {
          result = task.process(input);
        }
      } catch (error) {
        failure = error is TaskException
            ? error
            : TaskException(error.toString());
      }
      _trace(tag, name, id, failure == null ? 'end' : 'error');
      parent.send((id, result, failure));
      if (input == null) break;
      if (budget.spend(input.$1)) {
        _trace(tag, name, 'reopen', 'start');
        task.close();
        task = native = factory(options);
        _trace(tag, name, 'reopen', 'end');
      }
    }
  } catch (error) {
    _trace(tag, name, 'create', 'error');
    parent.send(
      error is TaskException ? error : TaskException(error.toString()),
    );
  } finally {
    try {
      native?.close();
    } finally {
      commands.close();
      _trace(tag, name, 'exit', 'return');
    }
  }
}

/// With MEDIAPIPE_VISION_TRACE=1, each worker's spawn, native creation,
/// native calls, result delivery and exit, tagged per worker, with a
/// millisecond clock, so a stall shows as a phase that never completes.
/// For diagnosing hangs; off by default.
final bool _tracing = Platform.environment['MEDIAPIPE_VISION_TRACE'] == '1';

void _trace(int tag, String name, Object id, String phase) {
  if (!_tracing) return;
  stderr.writeln(
    'MPTRACE ${DateTime.now().millisecondsSinceEpoch} pid=$pid tag=$tag '
    '$name #$id $phase',
  );
}

/// Reopening reads the model again, but MediaPipe has read it by the time a
/// task exists, so the app may delete the file. Holds it in memory while the
/// file is certainly present: [VisionTaskWorker.create] has not returned.
void _holdModel(VisionTaskOptions options) {
  final path = options.modelPath;
  if (path == null) return;
  try {
    holdModelBytes(options, File(path).readAsBytesSync().asUnmodifiableView());
  } on FileSystemException {
    // MediaPipe read the file a moment ago. If it is unreadable now, reopening
    // reads it again, as without this.
  }
}
