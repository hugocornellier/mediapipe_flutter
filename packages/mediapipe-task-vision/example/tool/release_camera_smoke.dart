// Hardware-only release check. Build explicitly with -t tool/release_camera_smoke.dart.
import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:mediapipe_face_camera/face_camera_controller.dart';
import 'package:mediapipe_face_camera/main.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = FaceCameraController();
  var maximumLandmarks = 0;
  session.addListener(() {
    for (final face in session.result?.faceLandmarks ?? []) {
      if (face.length > maximumLandmarks) maximumLandmarks = face.length;
    }
  });
  runApp(FaceCameraApp(controller: session));
  final watchdog = Timer(const Duration(seconds: 90), () {
    stderr.writeln('Release camera test timed out.');
    exit(1);
  });
  try {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw StateError('No camera available.');
    await session.start(cameras.first);
    while (session.processedFrames < 60) {
      if (session.error != null) throw StateError(session.error!);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (session.result?.timestampMilliseconds == null) {
      throw StateError('Expected a timestamped video result.');
    }
    stdout.writeln(
      'Release camera passed: ${session.processedFrames} frames, '
      '${session.result!.faceLandmarks.length} faces, '
      '$maximumLandmarks landmarks observed, '
      '${session.framesPerSecond.toStringAsFixed(1)} FPS, '
      '${session.inferenceMilliseconds.toStringAsFixed(1)} ms/frame.',
    );
    await session.stop();
    if (session.camera != null || session.running) {
      throw StateError('Camera did not stop.');
    }
    await session.close();
    watchdog.cancel();
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    await session.close();
    watchdog.cancel();
    exit(1);
  }
}
