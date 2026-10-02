import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';
import 'package:web/web.dart' as web;
import '../live/camera_selection.dart';
import '../live/frame_timings.dart';
import '../live/live_subjects.dart';
import '../live/live_task.dart';
import 'model_cache.dart';
import 'pipeline_trace.dart';
import 'test_hooks.dart';

extension type _VideoCallbacks(JSObject object) implements JSObject {
  external int requestVideoFrameCallback(JSFunction callback);
  external void cancelVideoFrameCallback(int handle);
}

extension type _TrackSettings(JSObject object) implements JSObject {
  external String? get facingMode;
}

extension type _FrameMetadata(JSObject object) implements JSObject {
  external double? get captureTime;
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
  final previewCanvas = web.HTMLCanvasElement();
  web.HTMLCanvasElement? workerOverlayCanvas;
  bool get useCanvasPreview => _isIOSBrowser;
  web.MediaStream? _stream;
  StreamSubscription<web.Event>? _trackEnded;
  late final JSFunction _visibility;
  Future<void> _operations = Future.value();
  Future<void>? _frame;

  /// The newest camera frame that arrived while [_frame] ran; it starts next.
  ({double arrived, double? captured})? _pending;
  Future<void>? _closing;
  final _clock = Stopwatch();
  bool _closed = false;
  bool _processingPaused = false;
  int _pauses = 0;
  bool _capturingPausedFrame = false;
  bool _opened = false;
  int _generation = 0;
  int? _callback;
  bool _videoCallback = false;
  double _lastVideoTime = -1;
  int _lastTimestamp = -1;
  int _timestampOffset = 0;
  String? _modelAsset;
  String? _warmUpSample;

  /// Supplies the model instead of the bundled asset: one of Google's other
  /// official models, or a file the user uploaded. Null uses the asset.
  Future<Uint8List> Function()? modelLoader;
  bool running = false;
  bool changing = false;
  bool initializing = false;
  String? error;

  /// The frame on screen when processing paused, which the view draws with
  /// Flutter while [previewHidden]; null if it could not be captured.
  ui.Image? pausedFrame;

  /// Whether the view leaves its platform views out of the scene: while
  /// processing is paused, once the paused frame is captured (or failed).
  /// Safari gives every Flutter layer drawn over a platform view a canvas of
  /// its own, a full-screen WebGL surface redrawn each frame, so a drawer
  /// scrolled over the feed paid for two; without them the page is one.
  bool get previewHidden => _processingPaused && !_capturingPausedFrame;

  /// Why the demo moved from GPU to CPU, when the browser refused the GPU.
  String? notice;
  T? result;
  List<CameraDescription> cameras = const [];
  CameraDescription? description;
  Size? frameSize;

  /// The preview's width over its height, as the camera view lays it out,
  /// or null before the first frame.
  double? get previewAspect {
    final size = frameSize;
    if (size == null || size.height == 0) return null;
    return size.width / size.height;
  }

  int frameRotationDegrees = 0;
  DeviceOrientation deviceOrientation = DeviceOrientation.landscapeLeft;
  Delegate delegate = Delegate.cpu;
  int processedFrames = 0;

  /// Camera frames never processed. A frame that arrives during inference
  /// waits for it; it is skipped only if a newer one arrives first.
  int skippedFrames = 0;
  double inferenceMilliseconds = 0;
  double conversionMilliseconds = 0;
  double frameMilliseconds = 0;
  double _totalInference = 0, _totalConversion = 0, _totalFrame = 0;
  int _lastUiUpdateMilliseconds = 0;
  final _recent = RecentFrameTimings();
  bool get isFrontCamera =>
      description?.lensDirection == CameraLensDirection.front;
  bool get canSwitchCamera => hasFrontAndBackCameras(cameras);
  bool get _canUseWorkerOverlay => const {
    'Face Landmarker',
    'Hand Landmarker',
    'Pose Landmarker',
    'Gesture Recognizer',
    'Holistic Landmarker',
    'Face Detector',
    'Object Detector',
  }.contains(task.name);

  void setOverlayOptions({
    required bool connections,
    required bool points,
    required double scale,
  }) {
    if (task case final BrowserOverlayLiveTask overlayTask) {
      overlayTask.setOverlayOptions(
        connections: connections,
        points: points,
        mirrored: isFrontCamera,
        scale: scale,
      );
    }
  }

  double get averageInferenceMilliseconds =>
      processedFrames == 0 ? 0 : _totalInference / processedFrames;
  double get averageConversionMilliseconds =>
      processedFrames == 0 ? 0 : _totalConversion / processedFrames;
  double get averageFrameMilliseconds =>
      processedFrames == 0 ? 0 : _totalFrame / processedFrames;
  double get framesPerSecond => _clock.elapsedMicroseconds == 0
      ? 0
      : processedFrames * 1000000 / _clock.elapsedMicroseconds;

  /// The readout's figures, over the last [recentFrames] frames, so they
  /// follow the current speed.
  double get recentInferenceMilliseconds => _recent.inferenceMilliseconds;
  double get recentConversionMilliseconds => _recent.conversionMilliseconds;
  double get recentFrameMilliseconds => _recent.frameMilliseconds;
  double get recentFramesPerSecond => _recent.framesPerSecond;
  int get recentFrames => _recent.length;

  void _changed() {
    if (!_closed) notifyListeners();
  }

  /// A drawer or sheet covers the feed. Pause playback, capture and inference
  /// while it is open so camera work cannot delay scrolling, and let the view
  /// show the paused frame in place of the camera's platform views.
  void setProcessingPaused(bool paused) {
    if (_processingPaused == paused) return;
    _processingPaused = paused;
    final pause = ++_pauses;
    _disposePausedFrame();
    if (paused) {
      _pending = null;
      _cancelCallback();
      video.pause();
      unawaited(_capturePausedFrame(pause));
    } else {
      _capturingPausedFrame = false;
      // Resume playback even while a task is still opening: it starts on the
      // frames of a playing video, and a paused one would never deliver any.
      if (_stream != null) unawaited(_resumeProcessing());
    }
    _changed();
  }

  Future<void> _capturePausedFrame(int pause) async {
    _capturingPausedFrame = true;
    ui.Image? image;
    try {
      if (video.readyState >= 2 && frameSize != null) {
        final bitmap = await web.window.createImageBitmap(video).toDart;
        image = await ui_web.createImageFromImageBitmap(bitmap);
      }
    } catch (_) {
      // The view shows the feed's background instead.
    }
    if (pause != _pauses || _closed) {
      image?.dispose();
      return;
    }
    pausedFrame = image;
    _capturingPausedFrame = false;
    _changed();
  }

  void _disposePausedFrame() {
    pausedFrame?.dispose();
    pausedFrame = null;
  }

  Future<void> _resumeProcessing() async {
    try {
      await video.play().toDart;
      if (_processingPaused) {
        video.pause();
      } else if (!_closed && running) {
        _schedule(_generation);
      }
    } catch (failure) {
      if (!_closed && !_processingPaused && running) {
        error = _message(failure);
        running = false;
        _changed();
      }
    }
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
    final settings = _stream!.getVideoTracks().toDart.first.getSettings();
    final activeDirection =
        _directionFromFacingMode(_TrackSettings(settings).facingMode) ??
        description?.lensDirection;
    for (final device in devices.where((d) => d.kind == 'videoinput')) {
      final label = device.label.toLowerCase();
      final direction = device.deviceId == settings.deviceId
          ? activeDirection ?? _directionFromLabel(label)
          : _directionFromLabel(label);
      found.add(
        CameraDescription(
          name: device.deviceId,
          lensDirection: direction ?? CameraLensDirection.external,
          sensorOrientation: 0,
        ),
      );
    }
    if (found.isEmpty) return;
    if (_isMobileBrowser && found.length > 1) {
      if (cameraForLensDirection(found, CameraLensDirection.front) == null) {
        found.add(_facingCamera(CameraLensDirection.front));
      }
      if (cameraForLensDirection(found, CameraLensDirection.back) == null) {
        found.add(_facingCamera(CameraLensDirection.back));
      }
    }
    cameras = found;
    description = found.firstWhere(
      (c) => c.name == settings.deviceId,
      orElse: () => activeDirection == null
          ? found.first
          : cameraForLensDirection(found, activeDirection) ?? found.first,
    );
  }

  Future<void> switchCamera() {
    if (!canSwitchCamera || _closed) return Future.value();
    description = oppositeFacingCamera(cameras, description);
    result = null;
    if (!running) {
      _changed();
      return Future.value();
    }
    // Holistic's VIDEO graph requires one fixed frame size. Front and back
    // cameras can deliver different sizes, so it needs a fresh task too.
    if (task is FixedFrameSizeLiveTask) {
      return start(description: description);
    }
    final selected = description!;
    final generation = ++_generation;
    running = false;
    changing = true;
    initializing = false;
    error = null;
    _cancelCallback();
    _changed();
    return _enqueue(() async {
      await _releaseCamera(preservePreview: true);
      if (_closed || generation != _generation) return;
      try {
        if (task case final StatefulLiveTask stateful) stateful.forgetFrames();
        await _openCamera(selected, generation);
        if (_closed || generation != _generation) {
          await _release();
          return;
        }
        _resetTimings();
        _timestampOffset = _lastTimestamp;
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

  /// [warmUpSample] is an image asset the task runs on before processing
  /// camera frames; see [_warmUp].
  Future<void> start({
    CameraDescription? description,
    Delegate? delegate,
    String? modelAsset,
    String? warmUpSample,
  }) {
    if (_closed) return Future.error(StateError('Camera demo is closed.'));
    this.description = description ?? this.description;
    final selected = this.description;
    final asset = _modelAsset = modelAsset ?? _modelAsset;
    final sample = _warmUpSample = warmUpSample ?? _warmUpSample;
    final chosen = delegate ?? this.delegate;
    if (asset == null || selected == null) {
      return Future.error(StateError('No camera selected.'));
    }
    final generation = ++_generation;
    running = false;
    changing = true;
    initializing = true;
    error = null;
    if (chosen == Delegate.gpu) notice = null;
    result = null;
    _cancelCallback();
    _changed();
    return _enqueue(() async {
      final keepCamera = _stream != null && description == null;
      if (keepCamera) {
        await _releaseTask();
      } else {
        await _release(preservePreview: true);
      }
      // The iOS canvas still contains the last processed frame. Show the live
      // video beneath it until the replacement task draws its first frame.
      previewCanvas.style.visibility = 'hidden';
      if (_closed || generation != _generation) return;
      var taskReady = false;
      var fallBack = false;
      var cameraFailure = false;
      Future<void>? opening;
      try {
        if (!web.window.isSecureContext) {
          throw StateError('Camera access requires HTTPS or localhost.');
        }
        this.delegate = chosen;
        // Load the model and open the task while the camera starts: on a phone
        // each takes seconds and neither needs the other. Every path below
        // awaits it, so a task that opens late is still released.
        opening = _openTask(chosen, asset)..ignore();
        try {
          if (keepCamera) {
            // A rebuild of the platform view can pause the existing video even
            // though its camera track remains live.
            await video.play().toDart;
            if (_processingPaused) video.pause();
          } else {
            // Show the camera while the worker warms up. Frame processing still
            // starts only after warm-up has cleared the sample's tracking state.
            await _openCamera(selected, generation);
            _changed();
          }
        } catch (_) {
          cameraFailure = true;
          rethrow;
        }
        await opening;
        if (_closed || generation != _generation) {
          await _release();
          return;
        }
        final warmedUpTo = task is FixedFrameSizeLiveTask
            ? -1
            : await _warmUp(sample);
        taskReady = true;
        if (_closed || generation != _generation) {
          await _release();
          return;
        }
        if (_canUseWorkerOverlay && task is BrowserOverlayLiveTask) {
          final canvas = web.HTMLCanvasElement();
          if (testHooks) canvas.setAttribute('data-worker-overlay', '');
          canvas.style
            ..width = '100%'
            ..height = '100%'
            ..objectFit = 'contain'
            ..pointerEvents = 'none';
          try {
            await (task as BrowserOverlayLiveTask).attachOverlay(canvas);
            workerOverlayCanvas = canvas;
          } catch (_) {
            // A browser without transferable canvases keeps Flutter drawing.
            workerOverlayCanvas = null;
          }
        }
        _resetTimings();
        _timestampOffset = 0;
        _lastTimestamp = warmedUpTo;
        running = true;
        _schedule(generation);
      } catch (failure) {
        try {
          await opening;
        } catch (_) {
          // The failure reported below is the one that stopped the start.
        }
        if (generation == _generation) {
          // A browser without WebGL2 (or one that loses the context) fails
          // while the GPU task opens or warms up; the demo then uses CPU,
          // visibly, as the native demo does.
          if (chosen == Delegate.gpu && !taskReady && !cameraFailure) {
            notice = 'GPU unavailable, using CPU. ${_message(failure)}';
            fallBack = true;
          } else {
            error = _message(failure);
          }
        }
        // The CPU retry keeps the camera, which is usually open by now: stopping
        // it would unmount the preview while the stream restarts, and Chrome then
        // delivers no frames to the new stream (see LiveCameraView.build).
        if (fallBack) {
          await _releaseTask();
        } else {
          await _release();
        }
      } finally {
        if (generation == _generation) {
          changing = false;
          initializing = false;
          _changed();
        }
      }
      if (fallBack && !_closed && generation == _generation) {
        unawaited(start(delegate: Delegate.cpu));
      }
    });
  }

  Future<void> _openTask(Delegate chosen, String asset) async {
    final loader = modelLoader;
    final bytes = loader != null
        ? await loader()
        : await WebModelCache.load(asset);
    await task.open(chosen, bytes);
    _opened = true;
  }

  Future<void> _openCamera(CameraDescription selected, int generation) async {
    final constraints = <String, Object>{
      'width': {'ideal': 640},
      'height': {'ideal': 480},
      if (selected.lensDirection == CameraLensDirection.front ||
          selected.lensDirection == CameraLensDirection.back)
        'facingMode': {
          (_isMobileBrowser && selected.name != 'default'
              ? 'exact'
              : 'ideal'): selected.lensDirection == CameraLensDirection.front
              ? 'user'
              : 'environment',
        }
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
    if (_closed || generation != _generation) return;
    video.srcObject = _stream;
    _trackEnded = const web.EventStreamProvider<web.Event>('ended')
        .forTarget(_stream!.getVideoTracks().toDart.first)
        .listen((_) {
          if (_closed || _stream == null) return;
          error = 'Camera disconnected. Reconnect it and reopen this page.';
          unawaited(stop());
        });
    await video.play().toDart;
    if (video.videoWidth == 0 || video.videoHeight == 0) {
      await video.onLoadedMetadata.first.timeout(const Duration(seconds: 10));
    }
    if (_closed || generation != _generation) return;
    await _enumerate();
    if (_closed || generation != _generation) return;
    video.style.transform = isFrontCamera ? 'scaleX(-1)' : '';
    previewCanvas.style.transform = video.style.transform;
    frameSize = Size(video.videoWidth.toDouble(), video.videoHeight.toDouble());
    if (_processingPaused) video.pause();
  }

  void _resetTimings() {
    processedFrames = 0;
    skippedFrames = 0;
    _totalInference = 0;
    _totalConversion = 0;
    _totalFrame = 0;
    _recent.clear();
    _lastUiUpdateMilliseconds = 0;
    _pending = null;
    _lastVideoTime = -1;
    _clock
      ..reset()
      ..start();
  }

  void _schedule(int generation) {
    if (_closed ||
        !running ||
        _processingPaused ||
        generation != _generation ||
        _callback != null ||
        web.document.visibilityState == 'hidden') {
      return;
    }
    final callback = ((JSNumber now, JSObject? metadata) {
      _callback = null;
      _onFrame(
        generation,
        now.toDartDouble,
        metadata == null ? null : _FrameMetadata(metadata).captureTime,
      );
    }).toJS;
    if (video.has('requestVideoFrameCallback')) {
      _videoCallback = true;
      _callback = _VideoCallbacks(video).requestVideoFrameCallback(callback);
    } else {
      _videoCallback = false;
      _callback = web.window.requestAnimationFrame(
        ((double now) {
          _callback = null;
          _onFrame(generation, now, null);
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

  // TODO: Use live stream mode once LIVE_STREAM is split from VIDEO, and
  // delete this hand-rolled copy of Google's frame dropping. See
  // RunningMode.liveStream in mediapipe_vision.
  void _onFrame(int generation, double arrived, double? captured) {
    if (_closed || !running || _processingPaused || generation != _generation) {
      return;
    }
    _schedule(generation);
    if (video.currentTime == _lastVideoTime) return;
    _lastVideoTime = video.currentTime;
    if (_frame != null) {
      // Starting the newest waiting frame as soon as inference finishes keeps
      // the worker busy; waiting for the next camera frame instead left it
      // idle for up to a frame interval, halving the rate once a frame took
      // just over one.
      if (_pending != null) skippedFrames++;
      _pending = (arrived: arrived, captured: captured);
      return;
    }
    _begin(generation, arrived, captured);
  }

  void _begin(int generation, double arrived, double? captured) {
    final timestamp = math.max(
      _lastTimestamp + 1,
      _timestampOffset + _clock.elapsedMilliseconds,
    );
    _lastTimestamp = timestamp;
    _frame = () async {
      web.ImageBitmap? bitmap;
      final trace = PipelineTrace.enabled
          ? (PipelineFrame(timestamp, delegate.name, arrived, captured)
              ..started = PipelineTrace.now())
          : null;
      final whole = Stopwatch()..start();
      try {
        final conversion = Stopwatch()..start();
        bitmap = await web.window.createImageBitmap(video).toDart;
        final width = bitmap.width, height = bitmap.height;
        if (useCanvasPreview) {
          // iOS WebKit can composite a live <video> at the wrong scale even
          // while createImageBitmap and detections see the full frame. Paint
          // those same pixels into a canvas so preview and overlay agree.
          if (previewCanvas.width != width || previewCanvas.height != height) {
            previewCanvas
              ..width = width
              ..height = height;
          }
          (previewCanvas.getContext('2d') as web.CanvasRenderingContext2D)
              .drawImage(bitmap, 0, 0);
          previewCanvas.style.visibility = 'visible';
        }
        conversion.stop();
        trace?.bitmap = PipelineTrace.now();
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
        trace?.detected = PipelineTrace.now();
        if (_closed || generation != _generation) return;
        frameSize = Size(width.toDouble(), height.toDouble());
        result = detected;
        if (workerOverlayCanvas != null &&
            task is BrowserOverlayLiveTask &&
            !(task as BrowserOverlayLiveTask).overlayActive) {
          workerOverlayCanvas = null;
        }
        processedFrames++;
        if (testHooks) {
          video.setAttribute(
            'data-processed-frames',
            processedFrames.toString(),
          );
          video.setAttribute('data-delegate', delegate.name);
          video.setAttribute('data-timestamp', timestamp.toString());
          final count = liveSubjectCount(detected);
          video.setAttribute('data-subjects', count.subjects.toString());
          video.setAttribute('data-landmarks', count.points.toString());
          final detections = switch (detected) {
            FaceDetectorResult(:final detections) => detections.length,
            ObjectDetectorResult(:final detections) => detections.length,
            _ => null,
          };
          if (detections != null) {
            video.setAttribute('data-detections', detections.toString());
          }
        }
        conversionMilliseconds = conversion.elapsedMicroseconds / 1000;
        inferenceMilliseconds = inference.elapsedMicroseconds / 1000;
        frameMilliseconds = whole.elapsedMicroseconds / 1000;
        _totalConversion += conversionMilliseconds;
        _totalInference += inferenceMilliseconds;
        _totalFrame += frameMilliseconds;
        _recent.add(
          inference: inferenceMilliseconds,
          conversion: conversionMilliseconds,
          frame: frameMilliseconds,
          finishedMicroseconds: _clock.elapsedMicroseconds,
        );
        // The worker paints landmark overlays at camera rate. Rebuilding the
        // Flutter page at that same rate competes with touch scrolling on
        // mobile Safari; its readouts need only a few updates per second.
        final elapsed = _clock.elapsedMilliseconds;
        if (PipelineTrace.enabled ||
            workerOverlayCanvas == null ||
            processedFrames == 1 ||
            elapsed - _lastUiUpdateMilliseconds >= 100) {
          _lastUiUpdateMilliseconds = elapsed;
          _changed();
        }
        if (trace != null) {
          trace.handled = PipelineTrace.now();
          trace.faces = detected is FaceLandmarkerResult
              ? detected.faceLandmarks.length
              : -1;
          // The frame that paints this result, then the next browser frame,
          // by which time the compositor has taken it. The microtask runs once
          // the frame's task ends, after every post-frame callback.
          SchedulerBinding.instance.addPostFrameCallback((_) {
            scheduleMicrotask(() => trace.built = PipelineTrace.now());
            trace.frame =
                SchedulerBinding
                    .instance
                    .currentSystemFrameTimeStamp
                    .inMicroseconds /
                1000;
            web.window.requestAnimationFrame(
              ((double _) {
                trace.painted = PipelineTrace.now();
                PipelineTrace.add(trace);
              }).toJS,
            );
          });
        }
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
        final next = _pending;
        _pending = null;
        if (next != null &&
            running &&
            !_processingPaused &&
            !_closed &&
            generation == _generation) {
          _begin(generation, next.arrived, next.captured);
        }
      }
    }();
  }

  /// Runs the task on [sample], then on a blank frame of its size, before the
  /// camera starts. Its first call loads every model the task chains, and on
  /// GPU compiles their shaders; on the camera's first frame that stall made
  /// the start the slowest, most skipped part of a demo. Models past a
  /// detector run only once it finds something, hence a sample with a
  /// subject; the blank frame then clears the tracking the sample left.
  /// Returns the last timestamp used, which camera frames continue after.
  Future<int> _warmUp(String? sample) async {
    final browserTask = task;
    if (sample == null || browserTask is! BrowserLiveTask<T>) return -1;
    final data = await rootBundle.load(sample);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    var image = await web.window
        .createImageBitmap(web.Blob(<web.BlobPart>[bytes.toJS].toJS))
        .toDart;
    // Object Detector's sample is 4K. A first inference needs no more than a
    // camera frame, and the blank frame after it is as large as the sample.
    final longer = math.max(image.width, image.height);
    if (longer > 1280) {
      final full = image;
      try {
        image = await web.window
            .createImageBitmap(
              full,
              web.ImageBitmapOptions(
                resizeWidth: (full.width * 1280 / longer).round(),
                resizeHeight: (full.height * 1280 / longer).round(),
                resizeQuality: 'medium',
              ),
            )
            .toDart;
      } finally {
        full.close();
      }
    }
    final width = image.width, height = image.height;
    try {
      await browserTask.detectBrowserFrame(image, width, height, 0);
    } finally {
      image.close();
    }
    final blank = await web.window
        .createImageBitmap(web.ImageData(width.toJS, height))
        .toDart;
    try {
      await browserTask.detectBrowserFrame(blank, width, height, 1);
    } finally {
      blank.close();
    }
    if (task case final StatefulLiveTask stateful) stateful.forgetFrames();
    return 1;
  }

  Future<void> _release({bool preservePreview = false}) async {
    await _releaseCamera(preservePreview: preservePreview);
    await _releaseTask();
  }

  Future<void> _releaseCamera({bool preservePreview = false}) async {
    _pending = null;
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
    // Keep HtmlElementView mounted while a replacement stream opens. Removing
    // the video element can abort play() on a slower browser camera flip.
    if (!preservePreview) frameSize = null;
    result = null;
    _clock.stop();
  }

  Future<void> _releaseTask() async {
    _pending = null;
    _cancelCallback();
    await _frame;
    workerOverlayCanvas = null;
    if (_opened) {
      _opened = false;
      await task.close();
    }
  }

  Future<void> stop() {
    if (_closed) return _closing ?? Future.value();
    final generation = ++_generation;
    running = false;
    changing = true;
    initializing = false;
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
    ++_pauses;
    running = false;
    _disposePausedFrame();
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
      return 'Camera permission denied. Allow camera access in your browser, then reopen this page.';
    }
    if (text.contains('NotFoundError')) {
      return 'No camera found. Connect a webcam and reopen this page.';
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

bool get _isMobileBrowser {
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    return true;
  }
  final userAgent = web.window.navigator.userAgent.toLowerCase();
  return userAgent.contains('android') ||
      userAgent.contains('iphone') ||
      userAgent.contains('ipad') ||
      userAgent.contains('ipod') ||
      (userAgent.contains('macintosh') &&
          web.window.navigator.maxTouchPoints > 1);
}

bool get _isIOSBrowser {
  final userAgent = web.window.navigator.userAgent.toLowerCase();
  return userAgent.contains('iphone') ||
      userAgent.contains('ipad') ||
      userAgent.contains('ipod') ||
      (userAgent.contains('macintosh') &&
          web.window.navigator.maxTouchPoints > 1);
}

CameraDescription _facingCamera(CameraLensDirection direction) =>
    CameraDescription(
      name: direction == CameraLensDirection.front
          ? 'browser-default-front'
          : 'browser-default-back',
      lensDirection: direction,
      sensorOrientation: 0,
    );

CameraLensDirection? _directionFromFacingMode(String? facingMode) =>
    switch (facingMode) {
      'user' => CameraLensDirection.front,
      'environment' => CameraLensDirection.back,
      _ => null,
    };

CameraLensDirection? _directionFromLabel(String label) {
  if (label.contains('back') ||
      label.contains('rear') ||
      label.contains('environment')) {
    return CameraLensDirection.back;
  }
  if (label.contains('front') ||
      label.contains('user') ||
      label.contains('face')) {
    return CameraLensDirection.front;
  }
  return null;
}
