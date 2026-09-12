import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_face_camera/face_camera_controller.dart';
import 'package:mediapipe_face_camera/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real macOS camera supplies frames for official video inference',
    (tester) async {
      final session = FaceCameraController();
      await tester.pumpWidget(FaceCameraApp(controller: session));
      Future<void> waitFor(bool Function() ready) async {
        final timeout = Stopwatch()..start();
        while (!ready()) {
          if (session.error != null) fail(session.error!);
          if (timeout.elapsed > const Duration(seconds: 60)) {
            fail('Timed out waiting for the camera');
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await waitFor(
        () =>
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Start camera'),
                )
                .onPressed !=
            null,
      );
      await tester.tap(find.text('Start camera'));
      await waitFor(() => session.processedFrames >= 30);
      expect(session.result, isNotNull);
      expect(session.result!.imageWidth, greaterThan(0));
      expect(session.result!.timestampMilliseconds, greaterThan(0));
      for (final face in session.result!.detections) {
        expect(face.keypoints, hasLength(6));
      }
      // Diagnostic counts only; camera frames are neither saved nor uploaded.
      debugPrint(
        'Live camera: ${session.processedFrames} frames, '
        '${session.result!.detections.length} faces, '
        '${session.framesPerSecond.toStringAsFixed(1)} FPS, '
        '${session.inferenceMilliseconds.toStringAsFixed(1)} ms/frame',
      );
      await tester.tap(find.text('Stop camera'));
      await waitFor(() => !session.changing);
      expect(session.running, isFalse);
      expect(session.camera, isNull);
      await tester.tap(find.text('Start camera'));
      await waitFor(() => session.processedFrames >= 10 && session.running);
      await session.close();
      await tester.pumpWidget(const SizedBox());
    },
    skip: !const bool.fromEnvironment('CAMERA_HARDWARE_TEST'),
  );
}
