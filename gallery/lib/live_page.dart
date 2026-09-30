import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

import 'catalog.dart';
import 'live/live_camera_controller.dart';
import 'live/camera_geometry.dart';
import 'live/embedding_similarity.dart';
import 'live/live_camera_view.dart';
import 'live/live_registry.dart';
import 'live/mask_overlay.dart';
import 'live/overlay_visibility.dart';
import 'live/speed_history.dart';
import 'live/task_models.dart';
import 'live/task_settings.dart';
import 'live/live_output.dart';
import 'live/task_settings_panel.dart';
import 'ui/components.dart';
import 'ui/design.dart';
import 'ui/speed_chart.dart';
import 'ui/workspace.dart';

/// One live camera demo, whichever task the tile names.
///
/// Camera capture and timing live in [LiveCameraController]. This page shares
/// model settings, delegate selection and overlays between camera and image
/// inference for every vision demo in the live registry.
class LivePage extends StatefulWidget {
  const LivePage({
    super.key,
    required this.task,
    required this.platform,
    required this.officialMacosLandmarkTasks,
    this.initialStillImage = false,
    this.stillImagePicker,
    this.onOpenMenu,
  });

  final GalleryTask task;
  final TaskPlatform platform;
  final Set<String> officialMacosLandmarkTasks;
  final bool initialStillImage;
  final Future<XFile?> Function()? stillImagePicker;
  final VoidCallback? onOpenMenu;

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  late final LiveDemo _demo = liveDemoFor(widget.task.id)!;
  late final LiveTask<Object?> _task = _demo.task();
  late final LiveCameraController<Object?> _controller =
      LiveCameraController<Object?>(_task);
  late final List<TaskSetting> _settings =
      taskSettings[widget.task.runtimeId] ?? const [];
  late final List<TaskModel> _models =
      taskModels[widget.task.runtimeId] ?? const [];
  TaskModel? _model;
  String? _uploaded;
  String? _modelStatus;

  /// Bumped on every page rebuild, so the settings sheet, which lives on its
  /// own route, redraws when a setting, the model or a display toggle changes.
  final _revision = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _revision.value++;
    _refreshMask();
  }

  /// Image Segmenter draws its mask as Google's demo does, with a legend,
  /// rather than with the connections other tasks draw.
  bool get _segmenter => widget.task.runtimeId == 'image_segmenter';
  final _masks = SegmentationMaskImages();

  /// The result on screen: the still image's, or the camera's newest.
  Object? get _shownResult =>
      _mode == _VisionInputMode.image ? _imageResult : _controller.result;

  List<String> get _labels => switch (_shownResult) {
    SegmentationResult(:final labels) => labels,
    _ => const [],
  };

  bool get _confidenceMasks =>
      _segmenter && _task.settings.choice('outputConfidenceMasks') == 1;

  /// Builds the mask image for the result on screen in the chosen style.
  void _refreshMask() {
    if (!_segmenter) return;
    _masks.show(
      _shownResult is SegmentationResult
          ? _shownResult! as SegmentationResult
          : null,
      (
        confidence: _confidenceMasks,
        selectedClass: _task.settings.choice('confidenceClass'),
      ),
    );
  }

  CustomPainter _overlay(Object? result, PreviewTransform transform) =>
      _segmenter
      ? MaskOverlay(
          _masks,
          transform: transform,
          opacity: _task.settings.share('opacity'),
        )
      : _demo.overlay(result, transform, _showConnections, _showPoints);

  /// Google's color legend under the view, while classes are colored.
  List<Widget> _legend() => [
    if (_segmenter && !_confidenceMasks && _labels.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SegmenterLegend(_labels),
      ),
  ];

  late final List<VisionDelegate> _delegates =
      widget.task
          .capabilitiesFor(widget.platform, widget.officialMacosLandmarkTasks)
          .supportedDelegates
          .toList()
        ..sort((a, b) => a.index.compareTo(b.index));

  String? _error;
  bool _autoStarted = false;

  /// Each frame's inference time since the page opened, for the Stats chart.
  final _speed = SpeedHistory();
  final _speedClock = Stopwatch()..start();
  int _speedFrames = 0;
  bool _showStats = false;

  /// Overlays draw connections and boxes without individual points.
  bool get _showConnections => !debugHideOverlay;
  static const _showPoints = false;
  late _VisionInputMode _mode = widget.initialStillImage && _hasImageMode
      ? _VisionInputMode.image
      : _VisionInputMode.camera;
  Uint8List? _imageBytes;
  VisionImage? _imageInput;
  Size? _imageSize;
  String? _imageName;
  Object? _imageResult;
  VisionDelegate? _imageDelegate;
  double? _imageMilliseconds;
  String? _imageError;
  bool _imageBusy = false;
  int _imageRevision = 0;
  int _modeRevision = 0;
  Future<void> _imageOperations = Future.value();
  Future<void> _cameraStopped = Future.value();

  bool get _hasImageMode => widget.task.live;

  @override
  void initState() {
    super.initState();
    _controller.delegate = preferredDelegate(_delegates);
    _controller.addListener(_onControllerChanged);
    if (_mode == _VisionInputMode.camera) _findCameras();
  }

  void _onControllerChanged() {
    final frames = _controller.processedFrames;
    if (frames != _speedFrames) {
      _speedFrames = frames;
      // One notification per processed frame; a restart counts from zero.
      if (frames > 0 && _controller.running) {
        _speed.add(
          _controller.delegate,
          _controller.inferenceMilliseconds,
          _speedClock.elapsed,
        );
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _findCameras() async {
    try {
      await _controller.findCameras();
      if (!mounted) return;
      if (_controller.cameras.isEmpty) {
        setState(
          () => _error = 'No camera found. Connect a webcam and try again.',
        );
        return;
      }
      // Open the demo already running. Guarded so that pressing Stop, or
      // switching delegate, is never undone by a later rebuild.
      if (_mode == _VisionInputMode.camera &&
          _controller.description != null &&
          !_autoStarted) {
        _autoStarted = true;
        unawaited(_start());
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    _imageRevision++;
    _modeRevision++;
    _controller.removeListener(_onControllerChanged);
    _controller.close();
    _controller.dispose();
    _revision.dispose();
    _masks.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_mode != _VisionInputMode.camera) return;
    if (_controller.description == null) return;
    try {
      // Start on the current delegate where the task supports it, otherwise
      // on the preferred one (Object Detector is Metal-only on macOS).
      await _controller.start(
        delegate: _delegates.contains(_controller.delegate)
            ? _controller.delegate
            : preferredDelegate(_delegates),
        modelAsset: 'assets/models/${widget.task.model}',
        warmUpSample: 'assets/samples/${widget.task.sample}',
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  /// Rebuilds a running task with the changed value, as a delegate change
  /// does; a stopped one picks it up when it starts. A display setting only
  /// redraws.
  void _setSetting(String key, Object value) {
    setState(() => _task.settings[key] = value);
    if (_settings.any((setting) => setting.key == key && setting.display)) {
      return;
    }
    _restartCurrentMode();
  }

  void _setDelegate(VisionDelegate delegate) {
    setState(() => _controller.delegate = delegate);
    if (_mode == _VisionInputMode.image || _controller.running) {
      _restartCurrentMode();
    }
  }

  /// Downloads and verifies an official model before the task is rebuilt
  /// with it, so a failed download leaves the running model in place.
  Future<void> _chooseModel(TaskModel? model) async {
    if (model == null) {
      setState(() {
        _model = null;
        _uploaded = null;
        _modelStatus = null;
      });
      _controller.modelLoader = null;
      _restartCurrentMode(startCameraIfStopped: true);
      return;
    }
    setState(() => _modelStatus = 'Downloading ${model.name}…');
    try {
      final bytes = await downloadModel(model);
      if (!mounted) return;
      setState(() {
        _model = model;
        _uploaded = null;
        _modelStatus = null;
      });
      _controller.modelLoader = () async => bytes;
      _restartCurrentMode(startCameraIfStopped: true);
    } on Object catch (error) {
      if (mounted) setState(() => _modelStatus = '$error');
    }
  }

  /// A model file of the user's own, as MediaPipe Studio's Upload.
  Future<void> _upload() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'MediaPipe models', extensions: ['tflite', 'task']),
        ],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _model = null;
        _uploaded = file.name;
        _modelStatus = null;
      });
      _controller.modelLoader = () async => bytes;
      _restartCurrentMode(startCameraIfStopped: true);
    } on Object catch (error) {
      if (mounted) setState(() => _modelStatus = '$error');
    }
  }

  Widget _panel() => ListenableBuilder(
    listenable: Listenable.merge([_controller, _revision]),
    builder: (context, _) => TaskSettingsPanel(
      settings: _settings,
      values: _task.settings,
      delegates: _delegates,
      delegate: _controller.delegate,
      enabled: !_controller.changing,
      onChanged: _setSetting,
      onDelegate: _setDelegate,
      models: _models,
      model: _model,
      uploaded: _uploaded,
      modelStatus: _modelStatus,
      onModel: _chooseModel,
      onUpload: _upload,
      bundledModel: widget.task.model,
      standardModel: standardModelNames[widget.task.runtimeId] ?? 'Standard',
      labels: _labels,
    ),
  );

  Future<void> _flipCamera() async {
    try {
      await _controller.switchCamera();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _restartCurrentMode({bool startCameraIfStopped = false}) {
    if (_mode == _VisionInputMode.image) {
      if (_imageInput != null) unawaited(_detectImage());
    } else if (_controller.running || startCameraIfStopped) {
      unawaited(_start());
    }
  }

  Future<void> _setMode(_VisionInputMode mode) async {
    if (_mode == mode) return;
    ++_imageRevision;
    ++_modeRevision;
    setState(() {
      _mode = mode;
      _imageResult = null;
      _imageError = null;
      _imageBusy = false;
    });
    if (mode == _VisionInputMode.image) {
      try {
        _cameraStopped = _controller.stop();
        await _cameraStopped;
        if (mounted && _mode == mode && _imageInput != null && !_imageBusy) {
          await _detectImage();
        }
      } on Object catch (error) {
        if (mounted && _mode == mode) setState(() => _imageError = '$error');
      }
    } else {
      await _imageOperations;
      if (mounted && _mode == mode) {
        if (_controller.description == null) {
          await _findCameras();
        } else {
          await _start();
        }
      }
    }
  }

  Future<void> _chooseImage() async {
    final modeRevision = _modeRevision;
    try {
      final file =
          await (widget.stillImagePicker?.call() ??
              openFile(
                acceptedTypeGroups: const [
                  XTypeGroup(
                    label: 'Images',
                    extensions: ['jpg', 'jpeg', 'png', 'webp'],
                  ),
                ],
              ));
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        final image = frame.image;
        try {
          final rgba = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (rgba == null) throw StateError('Could not decode this image.');
          final input = VisionImage.fromPixels(
            pixels: rgba.buffer.asUint8List(
              rgba.offsetInBytes,
              rgba.lengthInBytes,
            ),
            width: image.width,
            height: image.height,
            format: VisionPixelFormat.rgba,
          );
          if (!mounted ||
              _mode != _VisionInputMode.image ||
              modeRevision != _modeRevision) {
            return;
          }
          setState(() {
            _imageBytes = bytes;
            _imageInput = input;
            _imageSize = Size(image.width.toDouble(), image.height.toDouble());
            _imageName = file.name;
            _imageResult = null;
            _imageError = null;
          });
          unawaited(_detectImage());
        } finally {
          image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } on Object catch (error) {
      if (mounted &&
          _mode == _VisionInputMode.image &&
          modeRevision == _modeRevision) {
        setState(() => _imageError = '$error');
      }
    }
  }

  Future<void> _detectImage() {
    final input = _imageInput;
    if (input == null) return Future.value();
    final revision = ++_imageRevision;
    var delegate = _controller.delegate;
    final modelLoader = _controller.modelLoader;
    setState(() {
      _imageBusy = true;
      _imageResult = null;
      _imageError = null;
    });
    final operation = _imageOperations.then((_) async {
      var opened = false;
      try {
        await _cameraStopped;
        final model = modelLoader != null
            ? await modelLoader()
            : await _bundledModelBytes();
        if (!mounted ||
            _mode != _VisionInputMode.image ||
            revision != _imageRevision) {
          return;
        }
        try {
          await _task.open(delegate, model, mode: RunningMode.image);
        } on Object {
          // GPU is only the default; a platform that refuses it gets CPU.
          if (delegate != VisionDelegate.gpu) rethrow;
          delegate = VisionDelegate.cpu;
          _controller.delegate = delegate;
          await _task.open(delegate, model, mode: RunningMode.image);
        }
        opened = true;
        if (!mounted ||
            _mode != _VisionInputMode.image ||
            revision != _imageRevision) {
          return;
        }
        final inference = Stopwatch()..start();
        final result = await _task.detectImage(input);
        inference.stop();
        if (mounted &&
            _mode == _VisionInputMode.image &&
            revision == _imageRevision) {
          setState(() {
            _imageResult = result;
            _imageDelegate = delegate;
            _imageMilliseconds = inference.elapsedMicroseconds / 1000;
          });
        }
      } on Object catch (error) {
        if (mounted &&
            _mode == _VisionInputMode.image &&
            revision == _imageRevision) {
          setState(() => _imageError = '$error');
        }
      } finally {
        try {
          if (opened) await _task.close();
        } on Object catch (error) {
          if (mounted &&
              _mode == _VisionInputMode.image &&
              revision == _imageRevision) {
            setState(() => _imageError ??= '$error');
          }
        }
        if (mounted &&
            _mode == _VisionInputMode.image &&
            revision == _imageRevision) {
          setState(() => _imageBusy = false);
        }
      }
    });
    _imageOperations = operation;
    return operation;
  }

  Future<Uint8List> _bundledModelBytes() async {
    final data = await rootBundle.load('assets/models/${widget.task.model}');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  String _imageSummary(Object result) => switch (result) {
    FaceLandmarkerResult(:final faceLandmarks) =>
      '${faceLandmarks.length} ${faceLandmarks.length == 1 ? 'face' : 'faces'} detected',
    FaceDetectorResult(:final detections) =>
      '${detections.length} ${detections.length == 1 ? 'face' : 'faces'} detected',
    HandLandmarkerResult(:final handLandmarks) =>
      '${handLandmarks.length} ${handLandmarks.length == 1 ? 'hand' : 'hands'} detected',
    GestureRecognizerResult(:final handLandmarks) =>
      '${handLandmarks.length} ${handLandmarks.length == 1 ? 'hand' : 'hands'} recognized',
    PoseLandmarkerResult(:final poseLandmarks) =>
      '${poseLandmarks.length} ${poseLandmarks.length == 1 ? 'pose' : 'poses'} detected',
    HolisticLandmarkerResult(:final poseLandmarks) =>
      poseLandmarks.isEmpty ? 'No pose detected' : 'Body landmarks detected',
    ObjectDetectorResult(:final detections) =>
      '${detections.length} ${detections.length == 1 ? 'object' : 'objects'} detected',
    ImageClassifierResult(:final classifications) =>
      '${classifications.firstOrNull?.categories.length ?? 0} classes returned',
    EmbeddingSimilarity(:final result) =>
      '${result.embeddings.length} embeddings generated',
    SegmentationResult(:final categoryMask) =>
      categoryMask == null
          ? 'No category mask returned'
          : 'Segmentation complete',
    _ => 'Analysis complete',
  };

  String get _id => widget.task.runtimeId.replaceAll('_', '-');

  @override
  Widget build(BuildContext context) {
    return TaskWorkspace(
      title: widget.task.title,
      onOpenMenu: widget.onOpenMenu,
      settings: _panel(),
      children: [
        TaskToolbar(
          task: widget.task,
          leading: _hasImageMode
              ? Segmented<_VisionInputMode>(
                  semanticsIdentifier: '$_id-mode',
                  key: ValueKey('$_id-mode'),
                  segments: [
                    (
                      value: _VisionInputMode.camera,
                      label: 'Camera',
                      icon: LucideIcons.video,
                      key: ValueKey('$_id-mode-camera'),
                    ),
                    (
                      value: _VisionInputMode.image,
                      label: 'Still image',
                      icon: LucideIcons.upload,
                      key: ValueKey('$_id-mode-image'),
                    ),
                  ],
                  selected: _mode,
                  onChanged: (mode) => unawaited(_setMode(mode)),
                )
              : null,
        ),
        if (_mode == _VisionInputMode.image)
          ..._stillImage()
        else
          ..._camera(_controller),
        ..._legend(),
        const SizedBox(height: 22),
        _outputCard(),
      ],
    );
  }

  Widget _outputCard() {
    final result = _shownResult;
    final output = liveOutput(result);
    if (output == null) {
      return OutputCard(
        title: 'Results',
        empty: _mode == _VisionInputMode.image
            ? 'Choose an image to see what the task finds.'
            : 'Results appear once the camera runs.',
      );
    }
    return OutputCard(
      key: ValueKey('$_id-output'),
      title: output.title,
      count: output.count,
      items: output.items,
      empty: output.empty,
    );
  }

  List<Widget> _stillImage() {
    final bytes = _imageBytes;
    final size = _imageSize;
    if (bytes == null || size == null) {
      return [
        StillCard(
          onChoose: _chooseImage,
          message: _imageError,
          error: _imageError != null,
        ),
      ];
    }
    final result = _imageResult;
    return [
      FeedFrame(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: size.width / size.height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(bytes, fit: BoxFit.fill),
                    LayoutBuilder(
                      builder: (context, constraints) => CustomPaint(
                        key: ValueKey('$_id-still-overlay'),
                        painter: _overlay(
                          result,
                          PreviewTransform.fit(
                            frameSize: size,
                            rotationDegrees: 0,
                            viewSize: constraints.biggest,
                            mirror: false,
                          ),
                        ),
                      ),
                    ),
                    if (_imageBusy)
                      const Center(child: CircularProgressIndicator()),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 14,
              bottom: 14,
              child: FeedButton(
                icon: LucideIcons.imageUp,
                tooltip: 'Change image',
                onPressed: _chooseImage,
              ),
            ),
          ],
        ),
      ),
      FeedStatus(
        parts: [
          ?_imageName,
          if (result != null) _imageSummary(result),
          if (result != null && _imageMilliseconds != null)
            'Inference ${_imageMilliseconds!.toStringAsFixed(1)} ms',
        ],
        delegate: result != null && _imageMilliseconds != null
            ? (_imageDelegate == VisionDelegate.gpu ? 'GPU' : 'CPU')
            : null,
      ),
      if (_imageError case final error?)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            error,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: Sizes.sm,
            ),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlineButton(
          icon: LucideIcons.upload,
          label: 'Change image',
          tooltip: 'Choose another image',
          onPressed: _chooseImage,
        ),
      ),
    ];
  }

  List<Widget> _camera(LiveCameraController<Object?> controller) {
    final error = _error ?? controller.error;
    return [
      FeedFrame(
        child: Stack(
          fit: StackFit.expand,
          children: [
            LiveCameraView(
              controller: controller,
              showConnections: _showConnections,
              showPoints: _showPoints,
              painter: (transform) => _overlay(controller.result, transform),
              placeholder: switch (error) {
                final String error => Text(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFF0F3F2)),
                ),
                null => const CircularProgressIndicator(),
              },
            ),
            if (controller.canSwitchCamera)
              Positioned(
                left: 14,
                bottom: 14,
                child: FeedButton(
                  icon: LucideIcons.rotateCcw,
                  tooltip: controller.isFrontCamera
                      ? 'Switch to back camera'
                      : 'Switch to front camera',
                  onPressed: controller.changing ? null : _flipCamera,
                ),
              ),
          ],
        ),
      ),
      FeedStatus(
        parts: controller.running
            ? [
                '${controller.recentFramesPerSecond.toStringAsFixed(1)} fps',
                '${controller.recentInferenceMilliseconds.toStringAsFixed(0)} ms',
              ]
            : const ['Stopped'],
        delegate: controller.delegate == VisionDelegate.gpu ? 'GPU' : 'CPU',
        trailing: OutlineButton(
          key: ValueKey('$_id-stats'),
          icon: LucideIcons.chartLine,
          label: 'Stats',
          tooltip: _showStats ? 'Hide stats' : 'Show stats',
          bordered: _showStats,
          onPressed: () => setState(() => _showStats = !_showStats),
        ),
      ),
      if (controller.notice case final notice?)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            notice,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: Sizes.xs,
            ),
          ),
        ),
      if (_showStats) ...[
        const SizedBox(height: 10),
        StatsCard(
          key: ValueKey('$_id-stats-card'),
          history: _speed,
          delegates: _delegates,
        ),
      ],
    ];
  }
}

enum _VisionInputMode { camera, image }
