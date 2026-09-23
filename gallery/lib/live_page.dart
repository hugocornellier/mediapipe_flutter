import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_vision/capabilities.dart';

import 'catalog.dart';
import 'live/live_camera_controller.dart';
import 'live/live_camera_view.dart';
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
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

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
          IconButton(
            icon: Icon(_showConnections ? Icons.grid_on : Icons.grid_off),
            tooltip: 'Connections',
            onPressed: () =>
                setState(() => _showConnections = !_showConnections),
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
