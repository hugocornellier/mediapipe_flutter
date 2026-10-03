import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

/// Owns camera capture and the official Face Landmarker in live stream mode
/// for this demo: every camera frame is submitted as it arrives, and the
/// task drops the frames it has no time for.
class FaceCameraController extends ChangeNotifier {
  CameraController? _camera;
  FaceLandmarker? _landmarker;
  StreamSubscription<FaceLandmarkerResult>? _results;

  /// When each frame not yet answered arrived, by timestamp.
  final _arrived = <int, int>{};
  int _lastResultMicroseconds = 0;
  Future<void> _operations = Future.value();
  Future<void>? _closing;
  final _clock = Stopwatch();
  int _generation = 0;
  int _lastTimestamp = -1;
  bool _closed = false;

  CameraController? get camera => _camera;
  bool running = false;
  bool changing = false;
  String? error;
  FaceLandmarkerResult? result;
  int processedFrames = 0;

  /// Camera frames the task dropped: one runs and the newest one waits.
  int get droppedFrames => _landmarker?.droppedFrames ?? 0;

  /// From when the task started the last frame to its result.
  double inferenceMilliseconds = 0;
  Delegate delegate = Delegate.cpu;
  double get framesPerSecond => _clock.elapsedMicroseconds == 0
      ? 0
      : processedFrames * 1000000 / _clock.elapsedMicroseconds;

  Future<void> _enqueue(Future<void> Function() action) {
    final operation = _operations.then((_) => action());
    // Keep future lifecycle operations usable even if a caller catches a failure.
    _operations = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  void _changed() {
    if (!_closed) notifyListeners();
  }

  Future<void> start(
    CameraDescription description, {
    Delegate delegate = Delegate.cpu,
  }) {
    if (_closed) return Future.error(StateError('Camera demo is closed.'));
    final generation = ++_generation;
    running = false;
    changing = true;
    error = null;
    result = null;
    _changed();
    return _enqueue(() async {
      await _release();
      if (_closed || generation != _generation) return;
      try {
        this.delegate = delegate;
        final data = await rootBundle.load('assets/face_landmarker.task');
        _landmarker = await FaceLandmarker.create(
          FaceLandmarkerOptions(
            delegate: delegate,
            modelBytes: data.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            ),
            runningMode: RunningMode.liveStream,
          ),
        );
        _results = _landmarker!.results.listen(
          (detection) => _onResult(detection, generation),
          onError: (Object failure) => _onError(failure, generation),
        );
        if (_closed || generation != _generation) {
          await _release();
          return;
        }
        final camera = CameraController(
          description,
          ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.bgra8888,
        );
        _camera = camera;
        await camera.initialize();
        if (_closed || generation != _generation) {
          await _release();
          return;
        }
        camera.addListener(_cameraChanged);
        processedFrames = 0;
        inferenceMilliseconds = 0;
        _lastTimestamp = -1;
        _lastResultMicroseconds = 0;
        _clock
          ..reset()
          ..start();
        await camera.startImageStream((image) => _onFrame(image, generation));
        if (_closed || generation != _generation) {
          await _release();
          return;
        }
        running = true;
      } catch (failure) {
        if (generation == _generation) error = _message(failure);
        await _release();
      } finally {
        if (generation == _generation) {
          changing = false;
          _changed();
        }
      }
    });
  }

  void _cameraChanged() {
    final description = _camera?.value.errorDescription;
    if (description != null && running) {
      error = description;
      unawaited(stop());
    }
  }

  /// Stamps and submits every frame as it arrives; the task decides which
  /// frames run.
  void _onFrame(CameraImage image, int generation) {
    if (!running || _closed || generation != _generation) return;
    final timestamp = math.max(_clock.elapsedMilliseconds, _lastTimestamp + 1);
    _lastTimestamp = timestamp;
    try {
      if (image.format.group != ImageFormatGroup.bgra8888 ||
          image.planes.length != 1) {
        throw StateError(
          'The macOS camera must supply one BGRA or RGBA plane.',
        );
      }
      final plane = image.planes.single;
      final frame = VisionImage.fromPixels(
        pixels: plane.bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: plane.bytesPerRow,
        format: image.format.raw == 'RGBA'
            ? VisionPixelFormat.rgba
            : VisionPixelFormat.bgra,
      );
      _arrived[timestamp] = _clock.elapsedMicroseconds;
      _landmarker!.detectAsync(frame, timestampMilliseconds: timestamp);
    } catch (failure) {
      _onError(failure, generation);
    }
  }

  void _onResult(FaceLandmarkerResult detection, int generation) {
    final now = _clock.elapsedMicroseconds;
    final timestamp = detection.timestampMilliseconds!;
    final arrived = _arrived.remove(timestamp);
    // The frames before it that got no result were dropped.
    _arrived.removeWhere((other, _) => other < timestamp);
    // The task started this frame when it arrived, or when the frame before
    // it finished.
    final started = math.max(arrived ?? now, _lastResultMicroseconds);
    _lastResultMicroseconds = now;
    if (!running || _closed || generation != _generation) return;
    result = detection;
    inferenceMilliseconds = (now - started) / 1000;
    processedFrames++;
    _changed();
  }

  void _onError(Object failure, int generation) {
    if (_closed || generation != _generation) return;
    error = _message(failure);
    unawaited(stop());
  }

  Future<void> stop() {
    if (_closed) return _closing ?? Future.value();
    final generation = ++_generation;
    running = false;
    changing = true;
    result = null;
    _clock.stop();
    _changed();
    return _enqueue(() async {
      await _release();
      if (generation == _generation) {
        changing = false;
        _changed();
      }
    });
  }

  Future<void> _release() async {
    final camera = _camera;
    _camera = null;
    camera?.removeListener(_cameraChanged);
    if (camera != null) {
      try {
        if (camera.value.isStreamingImages) await camera.stopImageStream();
      } catch (failure) {
        error ??= _message(failure);
      } finally {
        try {
          await camera.dispose();
        } catch (failure) {
          error ??= _message(failure);
        }
      }
    }
    final landmarker = _landmarker;
    _landmarker = null;
    try {
      // Runs the frames already submitted; their results are not shown.
      await landmarker?.dispose();
    } catch (failure) {
      error ??= _message(failure);
    }
    await _results?.cancel();
    _results = null;
    _arrived.clear();
    _clock.stop();
  }

  /// Stops capture, then releases the task after the frames it holds.
  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _generation++;
    running = false;
    return _closing = _enqueue(_release);
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}

String _message(Object error) {
  if (error is CameraException) {
    if (error.code.toLowerCase().contains('access') ||
        error.code.toLowerCase().contains('permission')) {
      return 'Camera access is unavailable. Allow this app in System Settings → '
          'Privacy & Security → Camera, then try again.';
    }
    return error.description ?? error.code;
  }
  return error.toString();
}
