import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

import 'face_camera_controller.dart';
import 'face_overlay.dart';
import 'main_fixture.dart' show FaceFixtureApp;

void main() =>
    runApp(Platform.isIOS ? const FaceFixtureApp() : const FaceCameraApp());

class FaceCameraApp extends StatelessWidget {
  const FaceCameraApp({super.key, this.controller});

  final FaceCameraController? controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'MediaPipe Face Camera',
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff63e6be),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xff111518),
    ),
    home: FaceCameraPage(controller: controller),
  );
}

class FaceCameraPage extends StatefulWidget {
  const FaceCameraPage({super.key, this.controller});

  final FaceCameraController? controller;

  @override
  State<FaceCameraPage> createState() => _FaceCameraPageState();
}

class _FaceCameraPageState extends State<FaceCameraPage>
    with WidgetsBindingObserver {
  late final session = widget.controller ?? FaceCameraController();
  List<CameraDescription> cameras = [];
  CameraDescription? selected;
  String? cameraError;
  bool loading = true;
  bool showConnections = true;
  bool showPoints = false;
  VisionDelegate delegate = switch (const String.fromEnvironment(
    'FACE_CAMERA_DELEGATE',
    defaultValue: 'cpu',
  )) {
    'cpu' => VisionDelegate.cpu,
    'gpu' => VisionDelegate.gpu,
    final value => throw ArgumentError.value(value, 'FACE_CAMERA_DELEGATE'),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      _loadCameras(
        autoStart: const bool.fromEnvironment('FACE_CAMERA_AUTOSTART'),
      ),
    );
  }

  Future<void> _loadCameras({bool autoStart = false}) async {
    setState(() {
      loading = true;
      cameraError = null;
    });
    try {
      final found = await availableCameras();
      if (!mounted) return;
      setState(() {
        cameras = found;
        selected = found.isEmpty ? null : found.first;
        loading = false;
      });
      if (autoStart && selected != null) {
        await session.start(selected!, delegate: delegate);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          cameraError = error.toString();
          loading = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Native permission dialogs make a macOS app inactive. Keep initialization
    // alive for that state; release capture when the app is actually hidden.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(session.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) {
      final camera = session.camera;
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MediaPipe · Face Landmarker',
                  style: TextStyle(
                    color: Color(0xff63e6be),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Live camera',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.circle,
                      size: 9,
                      color: session.running
                          ? const Color(0xff63e6be)
                          : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      session.running
                          ? 'Live'
                          : session.changing
                          ? 'Connecting…'
                          : 'Stopped',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 310,
                      child: DropdownButtonFormField<CameraDescription>(
                        key: ValueKey(selected),
                        initialValue: selected,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Camera',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final camera in cameras)
                            DropdownMenuItem(
                              value: camera,
                              child: Text(
                                camera.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: session.changing
                            ? null
                            : (camera) {
                                setState(() => selected = camera);
                                if (camera != null && session.running) {
                                  unawaited(
                                    session.start(camera, delegate: delegate),
                                  );
                                }
                              },
                      ),
                    ),
                    SegmentedButton<VisionDelegate>(
                      segments: const [
                        ButtonSegment(
                          value: VisionDelegate.cpu,
                          label: Text('CPU'),
                        ),
                        ButtonSegment(
                          value: VisionDelegate.gpu,
                          label: Text('GPU (Metal)'),
                        ),
                      ],
                      selected: {delegate},
                      onSelectionChanged: session.changing
                          ? null
                          : (selection) {
                              setState(() => delegate = selection.single);
                              if (session.running && selected != null) {
                                unawaited(
                                  session.start(selected!, delegate: delegate),
                                );
                              }
                            },
                    ),
                    FilledButton.icon(
                      onPressed: session.changing || selected == null
                          ? null
                          : () {
                              unawaited(
                                session.running
                                    ? session.stop()
                                    : session.start(
                                        selected!,
                                        delegate: delegate,
                                      ),
                              );
                            },
                      icon: Icon(
                        session.running
                            ? Icons.stop_rounded
                            : Icons.videocam_outlined,
                      ),
                      label: Text(
                        session.running ? 'Stop camera' : 'Start camera',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh cameras',
                      onPressed: session.changing || session.running
                          ? null
                          : _loadCameras,
                      icon: const Icon(Icons.refresh),
                    ),
                    FilterChip(
                      label: const Text('Connections'),
                      selected: showConnections,
                      onSelected: (value) =>
                          setState(() => showConnections = value),
                    ),
                    FilterChip(
                      label: const Text('Points'),
                      selected: showPoints,
                      onSelected: (value) => setState(() => showPoints = value),
                    ),
                  ],
                ),
                if (session.error ?? cameraError case final String error) ...[
                  const SizedBox(height: 12),
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xff090c0e),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child:
                          session.running &&
                              camera != null &&
                              camera.value.isInitialized
                          ? AspectRatio(
                              aspectRatio: camera.value.aspectRatio,
                              child: ClipRect(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CameraPreview(camera),
                                    IgnorePointer(
                                      child: CustomPaint(
                                        painter: FaceOverlay(
                                          session.result,
                                          showConnections: showConnections,
                                          showPoints: showPoints,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (loading || session.changing)
                                  const CircularProgressIndicator()
                                else
                                  const Icon(
                                    Icons.videocam_outlined,
                                    size: 42,
                                    color: Colors.white38,
                                  ),
                                const SizedBox(height: 16),
                                Text(
                                  loading
                                      ? 'Finding cameras…'
                                      : session.changing
                                      ? 'Opening camera…'
                                      : cameras.isEmpty
                                      ? 'No camera found. Connect one and refresh.'
                                      : 'Start the camera to see all facial landmarks.',
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    Text('${session.result?.faceLandmarks.length ?? 0} faces'),
                    Text(
                      '${session.framesPerSecond.toStringAsFixed(1)} landmark FPS',
                    ),
                    Text(
                      '${session.inferenceMilliseconds.toStringAsFixed(1)} ms / frame',
                    ),
                    Text(
                      '${session.result?.faceLandmarks.fold<int>(0, (sum, face) => sum + face.length) ?? 0} landmarks',
                    ),
                    const Text(
                      'Processed on this Mac',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
