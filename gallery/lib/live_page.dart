import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_vision/capabilities.dart';

import 'catalog.dart';
import 'live/live_camera_controller.dart';
import 'live/live_camera_view.dart';
import 'live/live_registry.dart';
import 'live/task_models.dart';
import 'live/task_settings.dart';
import 'live/task_settings_panel.dart';

/// One live camera demo, whichever task the tile names.
///
/// Capture, the VIDEO-mode task lifecycle, frame skipping, delegate switching
/// and timings all live in [LiveCameraController]; this screen only picks the
/// task and painter out of the registry and draws the controls.
class LivePage extends StatefulWidget {
  const LivePage({
    super.key,
    required this.task,
    required this.platform,
    required this.officialMacosLandmarkTasks,
  });

  final GalleryTask task;
  final TaskPlatform platform;
  final Set<String> officialMacosLandmarkTasks;

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

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _findCameras();
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
      if (_controller.description != null && !_autoStarted) {
        _autoStarted = true;
        unawaited(_start());
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.close();
    _controller.dispose();
    _revision.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_controller.description == null) return;
    try {
      // Start on the current delegate where the task supports it, otherwise
      // on the first it does (Object Detector is Metal-only on macOS).
      await _controller.start(
        delegate: _delegates.contains(_controller.delegate)
            ? _controller.delegate
            : _delegates.first,
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
    if (_controller.running) unawaited(_start());
  }

  void _setDelegate(VisionDelegate delegate) {
    _controller.delegate = delegate;
    if (_controller.running) {
      unawaited(_start());
    } else {
      setState(() {});
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
      unawaited(_start());
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
      unawaited(_start());
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
      unawaited(_start());
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

  void _openSettings() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: _panel(),
    ),
  );

  Future<void> _flipCamera() async {
    try {
      await _controller.switchCamera();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
    final busy = controller.changing;
    // A side panel where there is room for it, as in MediaPipe Studio;
    // otherwise a sheet behind a settings button.
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task.title),
        actions: [
          if (controller.canSwitchCamera)
            IconButton(
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
          if (!wide)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Settings',
              onPressed: _openSettings,
            ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _camera(theme, controller, busy, wide)),
          if (wide) ...[
            const VerticalDivider(width: 1),
            SizedBox(width: 340, child: _panel()),
          ],
        ],
      ),
    );
  }

  Widget _camera(
    ThemeData theme,
    LiveCameraController<Object?> controller,
    bool busy,
    bool wide,
  ) => Column(
    children: [
      Expanded(
        child: Container(
          color: Colors.black,
          width: double.infinity,
          child: LiveCameraView(
            controller: controller,
            painter: (transform) => _demo.overlay(
              controller.result,
              transform,
              _showConnections,
              _showPoints,
            ),
            placeholder: switch (_error ?? controller.error) {
              final String error => Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
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
