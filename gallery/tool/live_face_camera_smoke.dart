// Build this release target to verify both delegates with a physical camera.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_gallery/live/live_camera_controller.dart';
import 'package:mediapipe_gallery/live/live_tasks.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _SmokeWindow());
  try {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw StateError('No camera is available.');
    final results = <Map<String, Object?>>[];
    for (final delegate in [VisionDelegate.cpu, VisionDelegate.gpu]) {
      final controller = LiveCameraController<FaceLandmarkerResult>(
        FaceLandmarkerLiveTask(),
      );
      try {
        await controller.start(
          cameras.first,
          delegate: delegate,
          modelAsset: 'assets/models/face_landmarker.task',
        );
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (controller.processedFrames < 5 &&
            controller.error == null &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        final result = controller.result;
        if (controller.error case final error?) throw StateError(error);
        if (controller.processedFrames < 5 ||
            result == null ||
            result.imageWidth <= 0 ||
            result.imageHeight <= 0 ||
            result.timestampMilliseconds == null) {
          throw StateError('$delegate did not complete five camera frames.');
        }
        results.add({
          'delegate': delegate.name,
          'processed_frames': controller.processedFrames,
          'faces_in_latest_frame': result.faceLandmarks.length,
          'landmarks_in_latest_frame': result.faceLandmarks.isEmpty
              ? 0
              : result.faceLandmarks.first.length,
          'width': result.imageWidth,
          'height': result.imageHeight,
          'timestamp_ms': result.timestampMilliseconds,
          'latest_inference_ms': controller.inferenceMilliseconds,
          'average_inference_ms': controller.averageInferenceMilliseconds,
          'skipped_frames': controller.skippedFrames,
        });
      } finally {
        await controller.close();
        controller.dispose();
      }
    }
    stdout.writeln(
      'GALLERY_CAMERA_SMOKE ${jsonEncode({'event': 'complete', 'delegates': results})}',
    );
    exit(0);
  } catch (error, stack) {
    stdout.writeln(
      'GALLERY_CAMERA_SMOKE ${jsonEncode({'event': 'failed', 'error': '$error'})}',
    );
    stderr.writeln(stack);
    exit(1);
  }
}

final class _SmokeWindow extends StatelessWidget {
  const _SmokeWindow();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: Center(
        child: Text('Testing Live Face Mesh with the physical camera…'),
      ),
    ),
  );
}
