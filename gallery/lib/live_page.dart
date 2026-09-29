import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

import 'catalog.dart';
import 'gallery_content_surface.dart';
import 'gallery_task_header.dart';
import 'gallery_theme.dart';
import 'gallery_settings_scaffold.dart';
import 'live/live_camera_controller.dart';
import 'live/camera_geometry.dart';
import 'live/embedding_similarity.dart';
import 'live/live_camera_view.dart';
import 'live/live_registry.dart';
import 'live/task_models.dart';
import 'live/task_settings.dart';
import 'live/task_settings_panel.dart';

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
    this.framed = false,
  });

  final GalleryTask task;
  final TaskPlatform platform;
  final Set<String> officialMacosLandmarkTasks;
  final bool initialStillImage;
  final Future<XFile?> Function()? stillImagePicker;
  final VoidCallback? onOpenMenu;
  final bool framed;

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
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
  }

  late final List<VisionDelegate> _delegates =
      widget.task
          .capabilitiesFor(widget.platform, widget.officialMacosLandmarkTasks)
          .supportedDelegates
          .toList()
        ..sort((a, b) => a.index.compareTo(b.index));

  String? _error;
  bool _autoStarted = false;
  bool _showConnections = true;
  bool _showPoints = false;
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
  /// does; a stopped one picks it up when it starts.
  void _setSetting(String key, Object value) {
    setState(() => _task.settings[key] = value);
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
      connections: _showConnections,
      points: _showPoints,
      onConnections: (value) => setState(() => _showConnections = value),
      onPoints: (value) => setState(() => _showPoints = value),
    ),
  );

  void _openSettings() => _scaffoldKey.currentState?.openEndDrawer();

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
          await _task.open(delegate, model, mode: VisionRunningMode.image);
        } on Object {
          // GPU is only the default; a platform that refuses it gets CPU.
          if (delegate != VisionDelegate.gpu) rethrow;
          delegate = VisionDelegate.cpu;
          _controller.delegate = delegate;
          await _task.open(delegate, model, mode: VisionRunningMode.image);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
    final busy = controller.changing;
    // Wide layouts keep settings beside the preview; compact ones use a drawer.
    final wide = MediaQuery.sizeOf(context).width >= 900;
    // Phones cannot fit the centered header beside the actions, so the title
    // takes the toolbar's own slot and truncates instead of being overdrawn.
    final compact = MediaQuery.sizeOf(context).width < 600;
    return GallerySettingsScaffold(
      scaffoldKey: _scaffoldKey,
      framed: widget.framed,
      wide: wide,
      appBar: AppBar(
        primary: !wide,
        automaticallyImplyLeading: false,
        leading: widget.onOpenMenu == null
            ? null
            : IconButton(
                icon: const Icon(Icons.menu),
                tooltip: 'Open navigation',
                onPressed: widget.onOpenMenu,
              ),
        title: compact
            ? Text(
                widget.task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        flexibleSpace: compact
            ? null
            : GalleryTaskHeader(taskTitle: widget.task.title),
        actions: [
          if (!wide)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Settings',
              onPressed: _openSettings,
            ),
          if (_hasImageMode)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!compact) ...[
                    Text('MODE', style: GalleryTheme.label(theme)),
                    const SizedBox(width: 8),
                  ],
                  DropdownButtonHideUnderline(
                    child: DropdownButton<_VisionInputMode>(
                      key: ValueKey(
                        '${widget.task.runtimeId.replaceAll('_', '-')}-mode',
                      ),
                      style: compact ? theme.textTheme.bodyMedium : null,
                      value: _mode,
                      items: const [
                        DropdownMenuItem(
                          value: _VisionInputMode.camera,
                          child: Text('Camera'),
                        ),
                        DropdownMenuItem(
                          value: _VisionInputMode.image,
                          child: Text('Still image'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) unawaited(_setMode(value));
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      content: GalleryContentSurface(
        framed: widget.framed,
        child: _mode == _VisionInputMode.image
            ? _stillImage(theme, wide)
            : _camera(theme, controller, busy, wide),
      ),
      settings: _panel(),
    );
  }

  Widget _stillImage(ThemeData theme, bool wide) => Column(
    children: [
      Expanded(
        child: Container(
          color: GalleryTheme.preview,
          width: double.infinity,
          child: _imageBytes == null || _imageSize == null
              ? Center(
                  child: Text(
                    _imageError ?? 'Choose an image to analyze.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: GalleryTheme.white),
                  ),
                )
              : Center(
                  child: AspectRatio(
                    aspectRatio: _imageSize!.width / _imageSize!.height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(_imageBytes!, fit: BoxFit.fill),
                        LayoutBuilder(
                          builder: (context, constraints) => CustomPaint(
                            key: ValueKey(
                              '${widget.task.runtimeId.replaceAll('_', '-')}-still-overlay',
                            ),
                            painter: _demo.overlay(
                              _imageResult,
                              PreviewTransform.fit(
                                frameSize: _imageSize!,
                                rotationDegrees: 0,
                                viewSize: constraints.biggest,
                                mirror: false,
                              ),
                              _showConnections,
                              _showPoints,
                            ),
                          ),
                        ),
                        if (_imageBusy)
                          const Center(child: CircularProgressIndicator()),
                      ],
                    ),
                  ),
                ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_imageError != null && _imageBytes != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _imageError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            if (_imageName != null)
              Text(_imageName!, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (_imageResult != null) Text(_imageSummary(_imageResult!)),
            // Which delegate produced this result, so switching shows a change.
            if (_imageResult != null && _imageMilliseconds != null)
              Text(
                'Inference ${_imageMilliseconds!.toStringAsFixed(1)} ms on '
                '${_imageDelegate == VisionDelegate.gpu ? 'GPU' : 'CPU'}',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _chooseImage,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    _imageBytes == null ? 'Choose image' : 'Change image',
                  ),
                ),
                if (!wide && _delegates.length > 1)
                  SegmentedButton<VisionDelegate>(
                    segments: [
                      for (final delegate in _delegates)
                        ButtonSegment(
                          value: delegate,
                          label: Text(
                            delegate == VisionDelegate.gpu ? 'GPU' : 'CPU',
                          ),
                        ),
                    ],
                    selected: {_controller.delegate},
                    onSelectionChanged: _imageBusy
                        ? null
                        : (selection) => _setDelegate(selection.first),
                  ),
              ],
            ),
          ],
        ),
      ),
    ],
  );

  Widget _camera(
    ThemeData theme,
    LiveCameraController<Object?> controller,
    bool busy,
    bool wide,
  ) => Column(
    children: [
      Expanded(
        child: Container(
          color: GalleryTheme.preview,
          width: double.infinity,
          child: LiveCameraView(
            controller: controller,
            showConnections: _showConnections,
            showPoints: _showPoints,
            painter: (transform) => _demo.overlay(
              controller.result,
              transform,
              _showConnections,
              _showPoints,
            ),
            foreground: controller.canSwitchCamera
                ? Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          foregroundColor: GalleryTheme.white,
                        ),
                        icon: Icon(
                          defaultTargetPlatform == TargetPlatform.iOS
                              ? Icons.flip_camera_ios
                              : Icons.flip_camera_android,
                        ),
                        tooltip: controller.isFrontCamera
                            ? 'Switch to back camera'
                            : 'Switch to front camera',
                        onPressed: busy ? null : _flipCamera,
                      ),
                    ),
                  )
                : null,
            placeholder: switch (_error ?? controller.error) {
              final String error => Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: GalleryTheme.white),
              ),
              null => const CircularProgressIndicator(),
            },
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (controller.notice case final notice?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  notice,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            if (controller.running)
              Text(
                '${controller.recentFramesPerSecond.toStringAsFixed(1)} fps  ·  '
                '${controller.recentFrameMilliseconds.toStringAsFixed(1)} ms '
                'per frame over the last ${controller.recentFrames} '
                '${controller.delegate == VisionDelegate.gpu ? 'GPU' : 'CPU'} '
                'frames\n'
                'inference ${controller.recentInferenceMilliseconds.toStringAsFixed(1)} ms  ·  '
                'convert ${controller.recentConversionMilliseconds.toStringAsFixed(2)} ms  ·  '
                '${controller.skippedFrames} skipped',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!wide && _delegates.length > 1)
                  SegmentedButton<VisionDelegate>(
                    segments: [
                      for (final delegate in _delegates)
                        ButtonSegment(
                          value: delegate,
                          label: Text(
                            delegate == VisionDelegate.gpu ? 'GPU' : 'CPU',
                          ),
                        ),
                    ],
                    selected: {controller.delegate},
                    onSelectionChanged: busy
                        ? null
                        : (selection) => _setDelegate(selection.first),
                  ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

enum _VisionInputMode { camera, image }
