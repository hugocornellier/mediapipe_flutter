import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_vision/capabilities.dart';

import 'catalog.dart';
import 'live/live_camera_controller.dart';
import 'live/live_registry.dart';

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
  late final LiveCameraController<Object?> _controller =
      LiveCameraController<Object?>(_demo.task());
  late final List<VisionDelegate> _delegates =
      widget.task
          .capabilitiesFor(widget.platform, widget.officialMacosLandmarkTasks)
          .supportedDelegates
          .toList()
        ..sort((a, b) => a.index.compareTo(b.index));

  List<CameraDescription> _cameras = const [];
  CameraDescription? _selected;
  String? _error;
  bool _autoStarted = false;
  bool _showMesh = true;
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
      final cameras = await availableCameras();
      if (!mounted) return;
      setState(() {
        _cameras = cameras;
        _selected = cameras.isEmpty ? null : cameras.first;
      });
      // Open the demo already running. Guarded so that pressing Stop, or
      // switching delegate, is never undone by a later rebuild.
      if (_selected != null && !_autoStarted) {
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
    super.dispose();
  }

  Future<void> _start() async {
    final camera = _selected;
    if (camera == null) return;
    try {
      await _controller.start(
        camera,
        delegate: _controller.delegate,
        modelAsset: 'assets/models/${widget.task.model}',
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
    final camera = controller.camera;
    final busy = controller.changing;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task.title),
        actions: [
          IconButton(
            icon: Icon(_showMesh ? Icons.grid_on : Icons.grid_off),
            tooltip: 'Connections',
            onPressed: () => setState(() => _showMesh = !_showMesh),
          ),
          IconButton(
            icon: Icon(_showPoints ? Icons.blur_on : Icons.blur_off),
            tooltip: 'Points',
            onPressed: () => setState(() => _showPoints = !_showPoints),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              width: double.infinity,
              child: camera != null && camera.value.isInitialized
                  ? Center(
                      child: AspectRatio(
                        aspectRatio: camera.value.aspectRatio,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CameraPreview(camera),
                            CustomPaint(
                              painter: _demo.overlay(
                                controller.result,
                                _showMesh,
                                _showPoints,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        _error ??
                            controller.error ??
                            (_cameras.isEmpty
                                ? 'Looking for a camera…'
                                : 'Press Start to begin.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (controller.running)
                  Text(
                    '${controller.framesPerSecond.toStringAsFixed(1)} fps  ·  '
                    '${controller.averageFrameMilliseconds.toStringAsFixed(1)} ms '
                    'per frame over ${controller.processedFrames} '
                    '${controller.delegate == VisionDelegate.gpu ? 'GPU' : 'CPU'} '
                    'frames\n'
                    'inference ${controller.averageInferenceMilliseconds.toStringAsFixed(1)} ms  ·  '
                    'convert ${controller.averageConversionMilliseconds.toStringAsFixed(2)} ms  ·  '
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
                    if (_cameras.length > 1)
                      DropdownButton<CameraDescription>(
                        value: _selected,
                        onChanged: busy
                            ? null
                            : (value) => setState(() => _selected = value),
                        items: [
                          for (final camera in _cameras)
                            DropdownMenuItem(
                              value: camera,
                              child: Text(camera.name),
                            ),
                        ],
                      ),
                    if (_delegates.length > 1)
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
                            : (selection) {
                                controller.delegate = selection.first;
                                if (controller.running) {
                                  _start();
                                } else {
                                  setState(() {});
                                }
                              },
                      ),
                    FilledButton.icon(
                      onPressed: busy || _selected == null
                          ? null
                          : controller.running
                          ? () => controller.stop()
                          : _start,
                      icon: Icon(
                        controller.running ? Icons.stop : Icons.play_arrow,
                      ),
                      label: Text(
                        controller.running ? 'Stop camera' : 'Start camera',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
