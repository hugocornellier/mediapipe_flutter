import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../../../capabilities.dart';
import '../vision_task_backend.dart';
import 'native_interactive_segmenter.dart';
import 'native_ios_interactive_segmenter.dart';

/// Google's stateful MagicTouch pipeline on a persistent inference worker.
///
/// Select the interactive_segmenter task in build-hook configuration. Supports
/// CPU on macOS arm64 (macOS 14+) and through Google's iOS and Android SDKs.
/// Await [dispose] when finished.
///
/// ```dart
/// final task = await InteractiveSegmenter.create(
///   InteractiveSegmenterOptions(model: VisionModels.interactiveSegmenter),
/// );
/// final image = VisionImage.fromFile('photo.jpg');
/// await task.setImage(image);
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class InteractiveSegmenter {
  InteractiveSegmenter._(this.delegate, [this._backend]) {
    if (_backend == null) {
      _events.listen(_receive);
    } else {
      _events.close();
    }
  }

  /// Requested inference backend, fixed at creation.
  final VisionDelegate delegate;

  /// Google's Android SDK, through `mediapipe_vision`.
  final InteractiveSegmenterBackend? _backend;
  final _events = ReceivePort();
  final _ready = Completer<void>();
  final _exited = Completer<void>();
  final _pending = <int, Completer<SegmentationMask?>>{};
  SendPort? _commands;
  int _nextId = 0;
  bool _disposing = false;
  Future<void>? _disposeFuture;
  VisionTaskException? _failure;

  /// Load the official task bundle off the calling isolate.
  static Future<InteractiveSegmenter> create(
    InteractiveSegmenterOptions options,
  ) async {
    await options.prepareModel();
    if (Platform.isAndroid && interactiveSegmenterBackendFactory != null) {
      // Google's Java task takes either delegate; GPU is not yet declared
      // supported (see the capability query) until physical devices pass.
      return InteractiveSegmenter._(
        options.delegate,
        await interactiveSegmenterBackendFactory!(options),
      );
    }
    final support = await queryInteractiveSegmenterCapabilities();
    if (support.unavailableReasons[options.delegate] case final reason?) {
      throw VisionTaskException(reason);
    }
    final task = InteractiveSegmenter._(options.delegate);
    try {
      await Isolate.spawn(
        _runWorker,
        (task._events.sendPort, options),
        onError: task._events.sendPort,
        onExit: task._events.sendPort,
        debugName: 'MediaPipe Interactive Segmenter',
      );
    } catch (error, stack) {
      task._events.close();
      Error.throwWithStackTrace(error, stack);
    }
    await task._ready.future;
    return task;
  }

  /// Replace the image and reset the official image/stroke session.
  ///
  /// Subsequent segment requests reuse the same native task. Work is serialized
  /// in submission order, including calls queued before this future completes.
  Future<void> setImage(VisionImage image) async {
    _checkOpen();
    if (_backend case final backend?) return backend.setImage(image);
    await _request(image);
  }

  /// Segment using the full current stroke history, in input-image coordinates.
  ///
  /// Resubmit a shorter history to undo strokes. Empty histories are rejected
  /// because they break Google's native decoder graph. Clear the overlay in the
  /// UI when no strokes remain; call setImage to reset the native session.
  /// Each result owns its unmodified confidence values.
  Future<SegmentationMask> segment(List<SegmentationStroke> strokes) async {
    _checkOpen();
    if (strokes.isEmpty || strokes.length > 0xffffffff) {
      throw ArgumentError('Supply at least one stroke.');
    }
    final history = List<SegmentationStroke>.unmodifiable(strokes);
    if (_backend case final backend?) return backend.segment(history);
    return (await _request(history))!;
  }

  void _checkOpen() {
    if (_disposing) throw StateError('InteractiveSegmenter has been disposed.');
    if (_failure case final failure?) throw failure;
  }

  Future<SegmentationMask?> _request(Object? input) {
    final id = _nextId++;
    final completer = Completer<SegmentationMask?>();
    _pending[id] = completer;
    _commands!.send((id, input));
    return completer.future;
  }

  /// Drain pending image/stroke requests and close the task exactly once.
  Future<void> dispose() {
    _disposing = true;
    return _disposeFuture ??= _backend?.dispose() ?? _close();
  }

  Future<void> _close() async {
    try {
      if (_failure == null) await _request(null);
    } finally {
      await _exited.future;
    }
  }

  void _receive(dynamic event) {
    switch (event) {
      case SendPort port:
        _commands = port;
        _ready.complete();
      case (int id, SegmentationMask? result, VisionTaskException? error):
        final completer = _pending.remove(id);
        if (error != null) {
          completer?.completeError(error);
        } else {
          completer?.complete(result);
        }
      case VisionTaskException error:
        _fail(error);
      case List<dynamic> error:
        _fail(VisionTaskException('Worker failed: ${error.join('\n')}'));
      case null:
        if (!_ready.isCompleted || _pending.isNotEmpty || !_disposing) {
          _fail(
            const VisionTaskException('Interactive Segmenter worker exited.'),
          );
        }
        _events.close();
        _exited.complete();
    }
  }

  void _fail(VisionTaskException error) {
    _failure ??= error;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();
  }
}

Future<void> _runWorker((SendPort, InteractiveSegmenterOptions) initial) async {
  final (parent, options) = initial;
  final commands = ReceivePort();
  InteractiveSegmenterSession? native;
  try {
    native = Platform.isIOS
        ? IosInteractiveSegmenter(options)
        : NativeInteractiveSegmenter(options);
    parent.send(commands.sendPort);
    await for (final dynamic message in commands) {
      final (id, input) = message as (int, Object?);
      SegmentationMask? result;
      VisionTaskException? failure;
      try {
        switch (input) {
          case null:
            native.close();
          case VisionImage image:
            native.setImage(image);
          case List<SegmentationStroke> strokes:
            result = native.segment(strokes);
          default:
            throw StateError('Unknown segmenter command.');
        }
      } catch (error) {
        failure = error is VisionTaskException
            ? error
            : VisionTaskException(error.toString());
      }
      parent.send((id, result, failure));
      if (input == null) break;
    }
  } catch (error) {
    parent.send(
      error is VisionTaskException
          ? error
          : VisionTaskException(error.toString()),
    );
  } finally {
    try {
      native?.close();
    } finally {
      commands.close();
    }
  }
}
