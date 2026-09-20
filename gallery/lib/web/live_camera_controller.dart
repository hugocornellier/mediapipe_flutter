import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:web/web.dart' as web;
import '../live/live_task.dart';

extension type _VideoCallbacks(JSObject object) implements JSObject {
  external int requestVideoFrameCallback(JSFunction callback);
  external void cancelVideoFrameCallback(int handle);
}

/// Browser capture with the same gallery lifecycle, controls and result painter.
class LiveCameraController<T> extends ChangeNotifier {
  LiveCameraController(this.task) {
    _visibility = ((web.Event _) {
      if (web.document.visibilityState == 'hidden') {
        _cancelCallback();
      } else if (running) {
        _schedule(_generation);
      }
    }).toJS;
    web.document.addEventListener('visibilitychange', _visibility);
  }
  final LiveTask<T> task;
  final video = web.HTMLVideoElement()
    ..autoplay = true
    ..muted = true
    ..playsInline = true
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.objectFit = 'contain';
  web.MediaStream? _stream;
  StreamSubscription<web.Event>? _trackEnded;
  late final JSFunction _visibility;
  Future<void> _operations = Future.value();
  Future<void>? _frame;
  Future<void>? _closing;
  final _clock = Stopwatch();
  bool _closed = false;
  bool _opened = false;
  int _generation = 0;
  int? _callback;
  bool _videoCallback = false;
  double _lastVideoTime = -1;
  int _lastTimestamp = -1;
  String? _modelAsset;
  bool running = false;
  bool changing = false;
  String? error;
  T? result;
  List<CameraDescription> cameras = const [];
  CameraDescription? description;
  Size? frameSize;
  int frameRotationDegrees = 0;
  DeviceOrientation deviceOrientation = DeviceOrientation.landscapeLeft;
  VisionDelegate delegate = VisionDelegate.cpu;
  int processedFrames = 0;
  int skippedFrames = 0;
  double inferenceMilliseconds = 0;
  double conversionMilliseconds = 0;
  double frameMilliseconds = 0;
  double _totalInference = 0, _totalConversion = 0, _totalFrame = 0;
  bool get isFrontCamera =>
      description?.lensDirection == CameraLensDirection.front;
  bool get canSwitchCamera => cameras.length > 1;
  double get averageInferenceMilliseconds =>
      processedFrames == 0 ? 0 : _totalInference / processedFrames;
  double get averageConversionMilliseconds =>
      processedFrames == 0 ? 0 : _totalConversion / processedFrames;
  double get averageFrameMilliseconds =>
      processedFrames == 0 ? 0 : _totalFrame / processedFrames;
  double get framesPerSecond => _clock.elapsedMicroseconds == 0
      ? 0
      : processedFrames * 1000000 / _clock.elapsedMicroseconds;

  void _changed() {
    if (!_closed) notifyListeners();
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final future = _operations.then((_) => action());
    _operations = future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return future;
  }

  Future<List<CameraDescription>> findCameras() async {
    // Device enumeration may be empty until permission is granted. Let Start
    // request permission rather than incorrectly declaring that no camera exists.
    if (_closed) return cameras;
    cameras = const [
      CameraDescription(
        name: 'default',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 0,
      ),
    ];
    description ??= cameras.first;
    _changed();
    return cameras;
  }

  Future<void> _enumerate() async {
    final devices =
        (await web.window.navigator.mediaDevices.enumerateDevices().toDart)
            .toDart;
    final found = <CameraDescription>[];
    for (final device in devices.where((d) => d.kind == 'videoinput')) {
      final label = device.label.toLowerCase();
      found.add(
        CameraDescription(
          name: device.deviceId,
          lensDirection: label.contains('back') || label.contains('rear')
              ? CameraLensDirection.back
              : found.isEmpty
              ? CameraLensDirection.front
              : CameraLensDirection.external,
          sensorOrientation: 0,
        ),
      );
    }
    if (found.isEmpty) return;
    cameras = found;
    final settings = _stream!.getVideoTracks().toDart.first.getSettings();
    description = found.firstWhere(
      (c) => c.name == settings.deviceId,
      orElse: () => found.first,
    );
  }

  Future<void> switchCamera() {
    if (!canSwitchCamera || _closed) return Future.value();
    final index = cameras.indexOf(description ?? cameras.first);
    description = cameras[(index + 1) % cameras.length];
    result = null;
    if (running) return start();
    _changed();
    return Future.value();
  }

  Future<void> start({
    CameraDescription? description,
    VisionDelegate? delegate,
    String? modelAsset,
  }) {
    if (_closed) return Future.error(StateError('Camera demo is closed.'));
    this.description = description ?? this.description;
    final selected = this.description;
    final asset = _modelAsset = modelAsset ?? _modelAsset;
    final chosen = delegate ?? this.delegate;
    if (asset == null || selected == null) {
      return Future.error(StateError('No camera selected.'));
    }
    final generation = ++_generation;
    running = false;
    changing = true;
    error = null;
    result = null;
    _cancelCallback();
    _changed();
    return _enqueue(() async {
      await _release();
      if (_closed || generation != _generation) return;
      try {
        if (!web.window.isSecureContext) {
          throw StateError('Camera access requires HTTPS or localhost.');
        }
        this.delegate = chosen;
        final model = await rootBundle.load(asset);
        await task.open(
          chosen,
          model.buffer.asUint8List(model.offsetInBytes, model.lengthInBytes),
        );
        _opened = true;
        if (_closed || generation != _generation) {
          await _release();
          return;
        }
        final constraints = <String, Object>{
          'width': {'ideal': 640},
          'height': {'ideal': 480},
          if (selected.name == 'default')
            'facingMode': 'user'
          else
            'deviceId': {'exact': selected.name},
        };
        _stream = await web.window.navigator.mediaDevices
            .getUserMedia(
              web.MediaStreamConstraints(
                video: constraints.jsify()!,
                audio: false.toJS,
              ),
            )
            .toDart;
        if (_closed || generation != _generation) {
          await _release();
          return;
        }
        video.srcObject = _stream;
        _trackEnded = const web.EventStreamProvider<web.Event>('ended')
            .forTarget(_stream!.getVideoTracks().toDart.first)
            .listen((_) {
              if (_closed || generation != _generation) return;
              error =
                  'Camera disconnected. Reconnect it and press Start camera.';
              unawaited(stop());
            });
        await video.play().toDart;
        if (video.videoWidth == 0 || video.videoHeight == 0) {
          await video.onLoadedMetadata.first.timeout(
            const Duration(seconds: 10),
          );
        }
        await _enumerate();
        if (_closed || generation != _generation) {
          await _release();
          return;
        }
        video.style.transform = isFrontCamera ? 'scaleX(-1)' : '';
        frameSize = Size(
          video.videoWidth.toDouble(),
          video.videoHeight.toDouble(),
        );
        processedFrames = 0;
        skippedFrames = 0;
        _totalInference = 0;
        _totalConversion = 0;
        _totalFrame = 0;
        _lastVideoTime = -1;
        _lastTimestamp = -1;
        _clock
          ..reset()
          ..start();
        running = true;
        _schedule(generation);
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

  void _schedule(int generation) {
    if (_closed ||
        !running ||
        generation != _generation ||
        _callback != null ||
        web.document.visibilityState == 'hidden') {
      return;
    }
    final callback = ((JSAny? _, JSAny? _) {
      _callback = null;
      _onFrame(generation);
    }).toJS;
    if (video.has('requestVideoFrameCallback')) {
      _videoCallback = true;
      _callback = _VideoCallbacks(video).requestVideoFrameCallback(callback);
    } else {
      _videoCallback = false;
      _callback = web.window.requestAnimationFrame(
        ((double _) {
          _callback = null;
          _onFrame(generation);
        }).toJS,
      );
    }
  }

  void _cancelCallback() {
    final callback = _callback;
    _callback = null;
    if (callback == null) return;
    if (_videoCallback) {
      _VideoCallbacks(video).cancelVideoFrameCallback(callback);
    } else {
      web.window.cancelAnimationFrame(callback);
    }
  }

  void _onFrame(int generation) {
    if (_closed || !running || generation != _generation) return;
    _schedule(generation);
    if (video.currentTime == _lastVideoTime) return;
    _lastVideoTime = video.currentTime;
    if (_frame != null) {
      skippedFrames++;
      return;
    }
    final timestamp = math.max(_lastTimestamp + 1, _clock.elapsedMilliseconds);
    _lastTimestamp = timestamp;
    _frame = () async {
      web.ImageBitmap? bitmap;
      final whole = Stopwatch()..start();
      try {
        final conversion = Stopwatch()..start();
        bitmap = await web.window.createImageBitmap(video).toDart;
        final width = bitmap.width, height = bitmap.height;
        conversion.stop();
        if (_closed || generation != _generation) return;
        final browserTask = task;
        if (browserTask is! BrowserLiveTask<T>) {
          throw UnsupportedError('Task has no browser frame transport.');
        }
        final inference = Stopwatch()..start();
        final detected = await browserTask.detectBrowserFrame(
          bitmap,
          width,
          height,
          timestamp,
        );
        inference.stop();
        whole.stop();
        if (_closed || generation != _generation) return;
        frameSize = Size(width.toDouble(), height.toDouble());
        result = detected;
        processedFrames++;
        video.setAttribute('data-processed-frames', processedFrames.toString());
        video.setAttribute('data-delegate', delegate.name);
        video.setAttribute('data-timestamp', timestamp.toString());
        if (detected is FaceLandmarkerResult) {
          video.setAttribute(
            'data-face-count',
            detected.faceLandmarks.length.toString(),
          );
          video.setAttribute(
            'data-landmarks',
            detected.faceLandmarks.isEmpty
                ? '0'
                : detected.faceLandmarks.first.length.toString(),
          );
        }
        conversionMilliseconds = conversion.elapsedMicroseconds / 1000;
        inferenceMilliseconds = inference.elapsedMicroseconds / 1000;
        frameMilliseconds = whole.elapsedMicroseconds / 1000;
        _totalConversion += conversionMilliseconds;
        _totalInference += inferenceMilliseconds;
        _totalFrame += frameMilliseconds;
        _changed();
      } catch (failure) {
        if (!_closed && generation == _generation) {
          error = _message(failure);
          running = false;
          _cancelCallback();
          _changed();
          // Queue release behind the current frame; do not await ourselves.
          unawaited(_enqueue(_release));
        }
      } finally {
        bitmap?.close();
        _frame = null;
      }
    }();
  }

  Future<void> _release() async {
    _cancelCallback();
    await _trackEnded?.cancel();
    _trackEnded = null;
    final stream = _stream;
    _stream = null;
    if (stream != null) {
      for (final track in stream.getTracks().toDart) {
        track.stop();
      }
    }
    video.srcObject = null;
    await _frame;
    if (_opened) {
      _opened = false;
      await task.close();
    }
    frameSize = null;
    result = null;
    _clock.stop();
  }

  Future<void> stop() {
    if (_closed) return _closing ?? Future.value();
    final generation = ++_generation;
    running = false;
    changing = true;
    _cancelCallback();
    _changed();
    return _enqueue(() async {
      try {
        await _release();
      } finally {
        if (generation == _generation) {
          changing = false;
          _changed();
        }
      }
    });
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    ++_generation;
    running = false;
    _cancelCallback();
    web.document.removeEventListener('visibilitychange', _visibility);
    return _closing = _enqueue(_release);
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }

  String _message(Object failure) {
    final text = failure.toString();
    if (text.contains('NotAllowedError')) {
      return 'Camera permission denied. Allow camera access in your browser and press Start camera.';
    }
    if (text.contains('NotFoundError')) {
      return 'No camera found. Connect a webcam and press Start camera.';
    }
    if (text.contains('NotReadableError')) {
      return 'Camera is unavailable or in use by another application.';
    }
    if (text.contains('OverconstrainedError')) {
      return 'The selected camera is unavailable. Choose another camera.';
    }
    return text;
  }
}
