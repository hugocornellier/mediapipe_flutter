// Run with ../tool/test_camera_soak.py; this target requires a real camera.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_face_camera/face_camera_controller.dart';
import 'package:mediapipe_face_camera/face_overlay.dart';

const _seconds = int.fromEnvironment('CAMERA_SOAK_SECONDS', defaultValue: 900);
const _cycles = int.fromEnvironment('CAMERA_SOAK_CYCLES', defaultValue: 5);
const _portrait = String.fromEnvironment('CAMERA_SOAK_PORTRAIT');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = FaceCameraController();
  final elapsed = Stopwatch()..start();
  final latencies = _LatencyHistogram();
  final fixtureLatencies = _LatencyHistogram();
  FaceLandmarker? fixtureTask;
  var fixtureFrames = 0;
  var cycle = 0;
  var seen = 0;
  var totalFrames = 0;
  var faceFrames = 0;
  var maximumLandmarks = 0;
  int? previousTimestamp;
  String? validationFailure;
  var lastFrameAt = Duration.zero;

  void report(String event, [Map<String, Object?> fields = const {}]) {
    stdout.writeln(
      'CAMERA_SOAK ${jsonEncode({'event': event, 'elapsed_seconds': elapsed.elapsedMilliseconds / 1000, 'cycle': cycle, 'rss_bytes': ProcessInfo.currentRss, 'peak_rss_bytes': ProcessInfo.maxRss, ...fields})}',
    );
  }

  void check() {
    if (validationFailure != null) throw StateError(validationFailure!);
    if (session.error != null) throw StateError(session.error!);
    if (!session.running) {
      throw StateError('Capture stopped during the soak.');
    }
    if (elapsed.elapsed - lastFrameAt > const Duration(seconds: 15)) {
      throw StateError('No completed camera frame for 15 seconds.');
    }
  }

  session.addListener(() {
    final result = session.result;
    if (result == null || session.processedFrames <= seen) return;
    seen = session.processedFrames;
    totalFrames++;
    lastFrameAt = elapsed.elapsed;
    latencies.add(session.inferenceMilliseconds);
    final timestamp = result.timestampMilliseconds;
    if (result.imageWidth <= 0 ||
        result.imageHeight <= 0 ||
        timestamp == null ||
        (previousTimestamp != null && timestamp <= previousTimestamp!)) {
      validationFailure =
          'Invalid result dimensions or non-increasing timestamp.';
      return;
    }
    previousTimestamp = timestamp;
    if (result.faceLandmarks.isNotEmpty) faceFrames++;
    for (final face in result.faceLandmarks) {
      if (face.length > maximumLandmarks) maximumLandmarks = face.length;
      if (face.length != 478 ||
          face.any(
            (point) =>
                !point.x.isFinite || !point.y.isFinite || !point.z.isFinite,
          )) {
        validationFailure =
            'Expected 478 finite landmarks for every detected face.';
      }
    }
  });
  // A dedicated diagnostic screen keeps this explicitly requested capture alive
  // when macOS occludes its window. The normal demo still stops when hidden.
  runApp(_SoakApp(session));
  final watchdog = Timer(Duration(seconds: _seconds + _cycles * 45 + 120), () {
    report('failed', {'error': 'Camera soak watchdog expired.'});
    exit(1);
  });

  try {
    if (!kReleaseMode || _cycles < 1 || _seconds < _cycles * 10) {
      throw StateError(
        'Use a release build with at least 10 seconds per cycle.',
      );
    }
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw StateError('No camera available.');
    final portrait = VisionImage.fromPixels(
      pixels: base64Decode(_portrait),
      width: 301,
      height: 209,
      format: VisionPixelFormat.rgb,
    );
    final bundle = await rootBundle.load('assets/face_landmarker.task');
    report('start', {
      'requested_active_seconds': _seconds,
      'cycles': _cycles,
      'platform': Platform.operatingSystemVersion,
      'mode': 'release',
    });
    for (cycle = 1; cycle <= _cycles; cycle++) {
      seen = 0;
      previousTimestamp = null;
      latencies.clear();
      fixtureLatencies.clear();
      fixtureTask = await FaceLandmarker.create(
        FaceLandmarkerOptions(
          modelBytes: bundle.buffer.asUint8List(
            bundle.offsetInBytes,
            bundle.lengthInBytes,
          ),
          runningMode: VisionRunningMode.video,
          outputFaceBlendshapes: true,
          outputFacialTransformationMatrixes: true,
        ),
      );
      await session.start(cameras.first);
      lastFrameAt = elapsed.elapsed;
      while (session.processedFrames == 0) {
        check();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      check();
      // Measure active capture after its first frame, excluding startup time.
      final active = Stopwatch()..start();
      var sampledAt = 0;
      var sampledFrames = session.processedFrames;
      var sampledSkipped = session.skippedFrames;
      var sampledFixtureFrames = fixtureFrames;
      latencies.clear();
      report('capturing', {
        'width': session.result!.imageWidth,
        'height': session.result!.imageHeight,
      });
      final cycleSeconds =
          _seconds ~/ _cycles + (cycle <= _seconds % _cycles ? 1 : 0);
      while (active.elapsedMilliseconds < cycleSeconds * 1000) {
        check();
        final fixtureTimer = Stopwatch()..start();
        final knownFace = await fixtureTask.detectForVideo(
          portrait,
          timestampMilliseconds: fixtureFrames,
        );
        fixtureFrames++;
        fixtureLatencies.add(fixtureTimer.elapsedMicroseconds / 1000);
        if (knownFace.faceLandmarks.length != 1 ||
            knownFace.faceLandmarks.single.length != 478 ||
            knownFace.faceBlendshapes.single.length != 52 ||
            knownFace.facialTransformationMatrixes.single.values.length != 16 ||
            knownFace.faceLandmarks.single.any(
              (p) => !p.x.isFinite || !p.y.isFinite || !p.z.isFinite,
            )) {
          throw StateError(
            'Portrait replay lost its complete mesh/optional outputs.',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final now = active.elapsedMilliseconds;
        if (now - sampledAt >= 15000 || now >= cycleSeconds * 1000) {
          check();
          final frames = session.processedFrames;
          final skipped = session.skippedFrames;
          report('sample', {
            'active_seconds': now / 1000,
            'frames': frames,
            'window_frames': frames - sampledFrames,
            'window_seconds': (now - sampledAt) / 1000,
            'fps': (frames - sampledFrames) * 1000 / (now - sampledAt),
            'skipped': skipped,
            'window_skipped': skipped - sampledSkipped,
            'latency_p50_ms': latencies.percentile(0.50),
            'latency_p95_ms': latencies.percentile(0.95),
            'fixture_frames': fixtureFrames,
            'window_fixture_frames': fixtureFrames - sampledFixtureFrames,
            'fixture_latency_p50_ms': fixtureLatencies.percentile(0.50),
            'fixture_latency_p95_ms': fixtureLatencies.percentile(0.95),
          });
          sampledAt = now;
          sampledFrames = frames;
          sampledSkipped = skipped;
          sampledFixtureFrames = fixtureFrames;
          latencies.clear();
          fixtureLatencies.clear();
        }
      }
      await session.stop();
      await fixtureTask.dispose();
      fixtureTask = null;
      final stoppedFrames = session.processedFrames;
      await Future<void>.delayed(const Duration(seconds: 2));
      if (session.camera != null ||
          session.running ||
          session.changing ||
          session.result != null ||
          session.error != null ||
          session.processedFrames != stoppedFrames) {
        throw StateError(
          'Camera or inference continued after stop: ${session.error}',
        );
      }
      report('stopped', {'frames': stoppedFrames});
    }
    cycle = _cycles;
    await session.close();
    report('complete', {
      'total_frames': totalFrames,
      'fixture_frames': fixtureFrames,
      'frames_with_faces': faceFrames,
      'maximum_landmarks': maximumLandmarks,
      'completed_cycles': _cycles,
    });
    watchdog.cancel();
    exit(0);
  } catch (error, stack) {
    report('failed', {'error': error.toString()});
    stderr.writeln(stack);
    await session.close();
    await fixtureTask?.dispose();
    watchdog.cancel();
    exit(1);
  }
}

class _SoakApp extends StatelessWidget {
  const _SoakApp(this.session);

  final FaceCameraController session;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: Scaffold(
      appBar: AppBar(title: const Text('MediaPipe camera soak test')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text(
              'Running $_seconds active seconds across $_cycles cycles. '
              'Capture continues when this test window is hidden. '
              'No camera images are saved.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                await session.close();
                exit(1);
              },
              child: const Text('Stop test'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: AnimatedBuilder(
                animation: session,
                builder: (context, _) {
                  final camera = session.camera;
                  if (!session.running || camera == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return Center(
                    child: AspectRatio(
                      aspectRatio: camera.value.aspectRatio,
                      child: ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CameraPreview(camera),
                            CustomPaint(painter: FaceOverlay(session.result)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// Fixed memory: one-millisecond buckets, with the final bucket representing
// 2000 ms or longer. Never retain images, landmark results, or per-frame lists.
class _LatencyHistogram {
  final _buckets = Uint32List(2001);
  var _count = 0;

  void add(double milliseconds) {
    _buckets[milliseconds.round().clamp(0, _buckets.length - 1)]++;
    _count++;
  }

  int? percentile(double fraction) {
    if (_count == 0) return null;
    final target = (_count * fraction).ceil();
    var cumulative = 0;
    for (var i = 0; i < _buckets.length; i++) {
      cumulative += _buckets[i];
      if (cumulative >= target) return i;
    }
    return _buckets.length - 1;
  }

  void clear() {
    _buckets.fillRange(0, _buckets.length, 0);
    _count = 0;
  }
}
