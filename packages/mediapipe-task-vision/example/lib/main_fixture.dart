import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

import 'face_overlay.dart';

void main() => runApp(const FaceFixtureApp());

/// Interactive CPU inference on bundled portraits, including iOS simulators.
class FaceFixtureApp extends StatelessWidget {
  const FaceFixtureApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff63e6be),
        brightness: Brightness.dark,
      ),
    ),
    home: const FaceFixturePage(),
  );
}

class FaceFixturePage extends StatefulWidget {
  const FaceFixturePage({super.key});

  @override
  State<FaceFixturePage> createState() => _FaceFixturePageState();
}

class _FaceFixturePageState extends State<FaceFixturePage> {
  static const examples = {
    'landmark-ex1.jpg': 'Portrait',
    'iris-detection-ex1.jpg': 'Eyes',
    'group-shot-bounding-box-ex1.jpeg': 'Group',
  };
  FaceDetector? _detector;
  FaceLandmarker? _landmarker;
  Directory? _temporary;
  Future<void>? _operation;
  String _selected = examples.keys.first;
  bool _busy = true;
  bool _mesh = true;
  String? _error;
  FaceDetectorResult? _detections;
  FaceLandmarkerResult? _landmarks;

  @override
  void initState() {
    super.initState();
    _operation = _initialize();
  }

  Future<void> _initialize() async {
    try {
      _temporary = await Directory.systemTemp.createTemp(
        'mediapipe-portraits-',
      );
      final detectorModel = await rootBundle.load(
        'assets/blaze_face_short_range.tflite',
      );
      _detector = await FaceDetector.create(
        FaceDetectorOptions(
          modelBytes: detectorModel.buffer.asUint8List(
            detectorModel.offsetInBytes,
            detectorModel.lengthInBytes,
          ),
        ),
      );
      final meshModel = await rootBundle.load('assets/face_landmarker.task');
      _landmarker = await FaceLandmarker.create(
        FaceLandmarkerOptions(
          modelBytes: meshModel.buffer.asUint8List(
            meshModel.offsetInBytes,
            meshModel.lengthInBytes,
          ),
          numFaces: 2,
          outputFaceBlendshapes: true,
          outputFacialTransformationMatrixes: true,
        ),
      );
      if (mounted) await _infer();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _busy = false;
        });
      }
    }
  }

  Future<void> _infer() async {
    setState(() {
      _busy = true;
      _error = null;
      _landmarks = null;
      _detections = null;
    });
    try {
      final data = await rootBundle.load(
        'assets/fixtures/face_detection/$_selected',
      );
      final file = File('${_temporary!.path}/$_selected');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final image = VisionImage.fromFile(file.path);
      final detections = await _detector!.detectImage(image);
      final landmarks = await _landmarker!.detectImage(image);
      if (mounted) {
        setState(() {
          _detections = detections;
          _landmarks = landmarks;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    await _operation;
    await _detector?.dispose();
    await _landmarker?.dispose();
    await _temporary?.delete(recursive: true);
  }

  @override
  void dispose() {
    unawaited(_close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('MediaPipe · Face tasks')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'CPU · Still images',
              style: TextStyle(color: Color(0xff63e6be)),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: [
                for (final entry in examples.entries)
                  ButtonSegment(value: entry.key, label: Text(entry.value)),
              ],
              selected: {_selected},
              onSelectionChanged: _busy
                  ? null
                  : (selection) {
                      setState(() => _selected = selection.single);
                      _operation = _infer();
                    },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: _busy
                    ? const CircularProgressIndicator()
                    : _error != null
                    ? Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      )
                    : AspectRatio(
                        aspectRatio:
                            _landmarks!.imageWidth / _landmarks!.imageHeight,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              'assets/fixtures/face_detection/$_selected',
                              fit: BoxFit.fill,
                            ),
                            CustomPaint(
                              painter: FaceOverlay(
                                _landmarks,
                                showMesh: _mesh,
                                showPoints: false,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${_detections?.detections.length ?? 0} '
              '${_detections?.detections.length == 1 ? 'face' : 'faces'} detected',
            ),
            Text(
              '${_landmarks?.faceLandmarks.fold<int>(0, (n, points) => n + points.length) ?? 0} landmarks',
            ),
            Text(
              '${_landmarks?.faceBlendshapes.firstOrNull?.length ?? 0} expression scores per face',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show mesh'),
              value: _mesh,
              onChanged: (value) => setState(() => _mesh = value),
            ),
            const Text(
              'Bundled example photos · Processed on this device',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
