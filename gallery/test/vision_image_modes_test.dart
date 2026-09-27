import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_gallery/catalog.dart';
import 'package:mediapipe_gallery/live_page.dart';

import 'support/scripted_camera.dart';

void main() {
  const platform = TaskPlatform(
    operatingSystem: 'macos',
    architecture: 'arm64',
    version: '15.0',
  );
  const runtimeIds = {
    'face_detector',
    'face_landmarker',
    'gesture_recognizer',
    'hand_landmarker',
    'holistic_landmarker',
    'image_classifier',
    'image_embedder',
    'image_segmenter',
    'object_detector',
    'pose_landmarker',
  };
  final liveTasks = supportedTasks(
    platform,
    runtimeIds,
    runtimeIds,
  ).where((task) => task.live).toList();

  test('every camera vision task has an image-capable gallery page', () {
    expect(liveTasks.map((task) => task.runtimeId).toSet(), runtimeIds);
  });

  for (final task in liveTasks) {
    testWidgets('${task.title} offers camera and still image modes', (
      tester,
    ) async {
      final previous = CameraPlatform.instance;
      CameraPlatform.instance = ScriptedCamera(cameras: const []);
      addTearDown(() => CameraPlatform.instance = previous);

      await tester.pumpWidget(
        MaterialApp(
          home: LivePage(
            task: task,
            platform: platform,
            officialMacosLandmarkTasks: runtimeIds,
            initialStillImage: true,
          ),
        ),
      );
      await tester.pump();

      final mode = find.byKey(
        ValueKey('${task.runtimeId.replaceAll('_', '-')}-mode'),
      );
      expect(mode, findsOneWidget);
      expect(find.text('Choose image'), findsOneWidget);
      expect(find.text('Choose an image to analyze.'), findsOneWidget);

      await tester.tap(mode);
      await tester.pumpAndSettle();
      if (kIsWeb) {
        // Browser widget tests have no webcam permission or media stream.
        expect(find.text('Camera'), findsOneWidget);
        await tester.tap(find.text('Still image').last);
        await tester.pumpAndSettle();
        return;
      }
      await tester.tap(find.text('Camera').last);
      await tester.pumpAndSettle();
      expect(find.text('Choose image'), findsNothing);

      await tester.tap(mode);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Still image').last);
      await tester.pumpAndSettle();
      expect(find.text('Choose image'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
