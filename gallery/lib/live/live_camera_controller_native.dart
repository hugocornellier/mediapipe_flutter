import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

import 'camera_geometry.dart';
import 'camera_frame.dart';
import 'camera_selection.dart';
import 'live_task.dart';

/// Owns camera capture and one official VIDEO-mode task.
///
/// Camera lifecycle, the operation queue, generation guards, frame skipping,
/// timestamp monotonicity, timings and error capture are the same whichever
/// task is running, so they live here once and the task supplies only [LiveTask].
class LiveCameraController<T> extends ChangeNotifier {
  LiveCameraController(this.task);

  /// The task being demonstrated.
  final LiveTask<T> task;

  CameraController? _camera;
  bool _opened = false;
  Future<void> _operations = Future.value();
  Future<void>? _frame;
  Future<void>? _closing;
  final _clock = Stopwatch();
  int _generation = 0;
  int _lastTimestamp = -1;
  bool _closed = false;
  bool _disposed = false;

  CameraController? get camera => _camera;
  bool running = false;
  bool changing = false;
  String? error;

  /// Set when MediaPipe refused the GPU and capture fell back to CPU.
  String? notice;
  T? result;

  /// Cameras this device offers, in the order the platform reports them.
  List<CameraDescription> cameras = const [];

  /// The selected camera, whether or not capture is running.
  CameraDescription? description;

  /// Size of the last frame as the camera delivered it, before rotation.
  Size? frameSize;

  /// Clockwise rotation applied to the last frame to stand it upright.
  int frameRotationDegrees = 0;

  /// Orientation the last frame's rotation was computed for.
  DeviceOrientation deviceOrientation = DeviceOrientation.portraitUp;
  String? _modelAsset;

  /// Whether the demo is looking at the person holding the device.
  bool get isFrontCamera =>
      description?.lensDirection == CameraLensDirection.front;

  /// Whether there is another camera to flip to.
  bool get canSwitchCamera => hasFrontAndBackCameras(cameras);
  int processedFrames = 0;
  int skippedFrames = 0;
  double inferenceMilliseconds = 0;
  double conversionMilliseconds = 0;
  double frameMilliseconds = 0;
  double _totalInferenceMilliseconds = 0;
  double _totalConversionMilliseconds = 0;
  double _totalFrameMilliseconds = 0;

  /// CPU by default, deliberately. Metal wins on back-to-back frames but
  /// loses at camera cadence, because it goes cold in the ~30 ms between them.
  /// Measured on an M4 Max at 1080p with one face: tight loop 4.03 CPU vs 3.45
  /// GPU, at 33 ms spacing 9.03 CPU vs 10.80 GPU. The official Python API
  /// inverts the same way on the same runtime, so this is the delegate's
  /// behaviour rather than anything this wrapper does.
  VisionDelegate delegate = VisionDelegate.cpu;

  /// Mean inference time since capture last started. Starting is what happens
  /// when the delegate changes, so this compares like with like rather than
  /// mixing CPU and GPU frames into one figure.
  double get averageInferenceMilliseconds =>
      processedFrames == 0 ? 0 : _totalInferenceMilliseconds / processedFrames;

  /// Mean time spent building a [VisionImage] from the camera plane.
  double get averageConversionMilliseconds =>
      processedFrames == 0 ? 0 : _totalConversionMilliseconds / processedFrames;

  /// Mean wall time for a whole frame, so plumbing shows up as the gap between
  /// this and [averageInferenceMilliseconds].
  double get averageFrameMilliseconds =>
      processedFrames == 0 ? 0 : _totalFrameMilliseconds / processedFrames;
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
    if (!_disposed) notifyListeners();
  }

  /// Finds the cameras and selects the one a live demo should open with.
  ///
  /// Front first: every live tile here looks at the person holding the device,
  /// so the back camera is the deliberate choice rather than the default.
  Future<List<CameraDescription>> findCameras() async {
    final found = await availableCameras();
    if (_closed) return found;
    cameras = found;
    description ??= found.isEmpty
        ? null
        : found.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
            orElse: () => found.first,
          );
    _changed();
    return found;
  }

  /// Flips directly between the front and back cameras.
  Future<void> switchCamera() {
    if (!canSwitchCamera || _closed) return Future.value();
    description = oppositeFacingCamera(cameras, description);
    result = null;
    frameSize = null;
    if (!running) {
      _changed();
      return Future.value();
    }
    return start();
  }

  /// Starts capture on the selected camera.
  ///
  /// Every argument defaults to what the last start used, so flipping the
  /// camera or changing the delegate does not make the caller restate the rest.
  Future<void> start({
    CameraDescription? description,
    VisionDelegate? delegate,
    String? modelAsset,
  }) {
    if (_closed) return Future.error(StateError('Camera demo is closed.'));
    this.description = description ?? this.description;
    final chosen = delegate ?? this.delegate;
    final asset = _modelAsset = modelAsset ?? _modelAsset;
    final selected = this.description;
    if (selected == null || asset == null) {
      return Future.error(StateError('No camera selected.'));
    }
    final generation = ++_generation;
    running = false;
    changing = true;
    error = null;
    if (chosen == VisionDelegate.gpu) notice = null;
    result = null;
    _changed();
    return _enqueue(() async {
      await _release();
      if (_closed || generation != _generation) return;
      var fallBack = false;
      try {
        this.delegate = chosen;
        final data = await rootBundle.load(asset);
        await task.open(
          chosen,
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        _opened = true;
        if (_closed || generation != _generation) {
          await _release();
          return;
        }
        final camera = CameraController(
          selected,
          ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
              ? ImageFormatGroup.yuv420
              : ImageFormatGroup.bgra8888,
        );
        _camera = camera;
        await camera.initialize();
        if (_closed || generation != _generation) {
          await _release();
          return;
        }
        camera.addListener(_cameraChanged);
        frameSize = null;
        frameRotationDegrees = 0;
        processedFrames = 0;
        skippedFrames = 0;
        inferenceMilliseconds = 0;
        conversionMilliseconds = 0;
        frameMilliseconds = 0;
        _totalInferenceMilliseconds = 0;
        _totalConversionMilliseconds = 0;
        _totalFrameMilliseconds = 0;
        _lastTimestamp = -1;
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
        if (generation == _generation) {
          // The package never swaps delegates itself; the demo does, visibly.
          if (chosen == VisionDelegate.gpu && _refusedGpu(failure)) {
            notice = 'GPU unavailable, using CPU. ${_message(failure)}';
            fallBack = true;
          } else {
            error = _message(failure);
          }
        }
        await _release();
      } finally {
        if (generation == _generation) {
          changing = false;
          _changed();
        }
      }
      if (fallBack && !_closed && generation == _generation) {
        unawaited(start(delegate: VisionDelegate.cpu));
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

  void _onFrame(CameraImage image, int generation) {
    if (!running || _closed || generation != _generation) return;
    if (_frame != null) {
      skippedFrames++;
      return;
    }
    final timestamp = math.max(_clock.elapsedMilliseconds, _lastTimestamp + 1);
    _lastTimestamp = timestamp;
    _frame = _process(
      image,
      generation,
      timestamp,
    ).whenComplete(() => _frame = null);
  }

  Future<void> _process(
    CameraImage image,
    int generation,
    int timestamp,
  ) async {
    final timer = Stopwatch()..start();
    try {
      // The frame arrives in sensor layout on mobile, so work out the turn that
      // stands it upright. MediaPipe applies it and still answers in the
      // delivered frame's coordinates, so the overlay takes the same turn.
      final orientation = _camera?.value.deviceOrientation ?? deviceOrientation;
      final rotation = uprightRotationDegrees(
        width: image.width,
        height: image.height,
        sensorOrientation: _camera?.description.sensorOrientation ?? 0,
        isFrontCamera: isFrontCamera,
        deviceOrientation: orientation,
      );
      final conversion = Stopwatch()..start();
      final frame = visionImageFromCamera(image);
      conversion.stop();
      final inference = Stopwatch()..start();
      final detection = await task.detect(
        frame,
        timestamp,
        rotationDegrees: rotation,
      );
      inference.stop();
      if (_closed || generation != _generation) return;
      result = detection;
      frameSize = Size(image.width.toDouble(), image.height.toDouble());
      frameRotationDegrees = rotation;
      deviceOrientation = orientation;
      // Split so the readout distinguishes the task's own work from what this
      // demo spends getting a camera frame to it: building the VisionImage,
      // and the isolate hop the task worker makes to keep native pointers off
      // the calling isolate.
      conversionMilliseconds = conversion.elapsedMicroseconds / 1000;
      inferenceMilliseconds = inference.elapsedMicroseconds / 1000;
      frameMilliseconds = timer.elapsedMicroseconds / 1000;
      _totalConversionMilliseconds += conversionMilliseconds;
      _totalInferenceMilliseconds += inferenceMilliseconds;
      _totalFrameMilliseconds += frameMilliseconds;
      processedFrames++;
      _changed();
    } catch (failure) {
      if (_closed || generation != _generation) return;
      error = _message(failure);
      unawaited(stop());
    }
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
    // Tell the view now, before any await: CameraPreview listens to the
    // controller and would otherwise rebuild on it after dispose() and throw.
    // Rebuilding the ancestor first unmounts that preview instead.
    if (camera != null) _changed();
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
    await _frame;
    if (_opened) {
      _opened = false;
      try {
        await task.close();
      } catch (failure) {
        error ??= _message(failure);
      }
    }
    _clock.stop();
  }

  /// Waits for capture and in-flight inference to stop before releasing resources.
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
    _disposed = true;
    super.dispose();
  }
}

bool _refusedGpu(Object error) => switch (error) {
  FaceLandmarkerException(:final gpuUnavailable) => gpuUnavailable,
  FaceDetectorException(:final gpuUnavailable) => gpuUnavailable,
  _ => false,
};

String _message(Object error) {
  if (error is CameraException) {
    if (error.code.toLowerCase().contains('access') ||
        error.code.toLowerCase().contains('permission')) {
      final settings = switch (defaultTargetPlatform) {
        TargetPlatform.windows => 'Settings → Privacy & security → Camera',
        TargetPlatform.linux => 'your desktop or camera device permissions',
        TargetPlatform.android => 'Settings → Apps → Permissions → Camera',
        _ => 'System Settings → Privacy & Security → Camera',
      };
      return 'Camera access is unavailable. Allow this app in $settings, '
          'then try again.';
    }
    return error.description ?? error.code;
  }
  return error.toString();
}
