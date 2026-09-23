import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_gallery/live/live_camera_controller.dart';
import 'package:mediapipe_gallery/live/live_camera_view.dart';
import 'package:mediapipe_gallery/live/live_subjects.dart';
import 'package:mediapipe_gallery/main.dart';

import 'support/live_subject.dart';
import 'support/supplied_camera.dart';

// Hosted runners have no physical webcam. Replace capture only: the gallery,
// controller, frame conversion, worker and Google's native CPU task are real.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native desktop camera plugin registers and enumerates devices', (
    tester,
  ) async {
    expect(Platform.isLinux || Platform.isWindows, isTrue);
    expect(
      CameraPlatform.instance.runtimeType.toString(),
      'CameraDesktopPlugin',
    );
    expect(CameraPlatform.instance.supportsImageStreaming(), isTrue);
    await tester.runAsync(() async {
      final cameras = await CameraPlatform.instance.availableCameras();
      // An empty list is expected on hosted CI; enumeration must still work.
      expect(cameras, isA<List<CameraDescription>>());
    });
  });

  final subject = LiveSubject.selected;
  testWidgets(
    'gallery ${subject.task} CPU camera: RGBA/BGRA, switching, restart and '
    'cleanup',
    (tester) async {
      final original = CameraPlatform.instance;
      final frames = await tester.runAsync(sampleFrames);
      final camera = SuppliedCamera(frames!);
      CameraPlatform.instance = camera;
      LiveCameraController<Object?>? controller;
      try {
        await tester.pumpWidget(const GalleryApp());
        for (
          var i = 0;
          i < 100 && find.text(subject.tile).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
        }
        expect(find.text(subject.tile), findsOneWidget);
        // Linux offers GPU for face and hand; this test stays on the CPU
        // default. Windows has no GPU path.
        final gpuOffered = Platform.isLinux ? findsOneWidget : findsNothing;
        final tile = find.ancestor(
          of: find.text(subject.tile),
          matching: find.byType(Card),
        );
        expect(
          find.descendant(of: tile, matching: find.text('GPU')),
          gpuOffered,
        );
        await tester.tap(find.text(subject.tile));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        controller = tester
            .widget<LiveCameraView>(find.byType(LiveCameraView))
            .controller;
        final live = controller;
        final firstFrames = <String, List<LivePoint>>{};
        live.addListener(() {
          final subjects = liveSubjects(live.result);
          if (live.processedFrames == 1 && subjects.isNotEmpty) {
            firstFrames.putIfAbsent(
              live.description!.name,
              () => subjects.first,
            );
          }
        });
        camera.deliverFrames = true;
        await waitForFrames(tester, live);
        await tester.pump();
        expect(find.text('GPU'), gpuOffered);
        expect(find.byType(SegmentedButton<VisionDelegate>), gpuOffered);
        expect(live.delegate, VisionDelegate.cpu);
        expect(live.frameRotationDegrees, 0);

        // Switch from the padded RGBA camera to padded BGRA without closing the
        // page. The same sample must keep its landmarks and colour order.
        await tester.tap(find.byTooltip('Switch to back camera'));
        await tester.pump();
        await waitForFrames(tester, live);
        await tester.pump();
        // Later VIDEO results depend on how many tracking frames arrived while
        // the UI was pumping. Compare the first frame of each fresh task.
        final before = firstFrames['supplied-rgba']!;
        final after = firstFrames['supplied-bgra']!;
        for (var i = 0; i < before.length; i++) {
          expect(after[i].x, closeTo(before[i].x, 1e-4));
          expect(after[i].y, closeTo(before[i].y, 1e-4));
        }
        expect(live.description!.name, 'supplied-bgra');
        expect(camera.disposed, 1);

        expect(find.byType(FilledButton), findsNothing);
        await tester.runAsync(live.stop);
        await tester.runAsync(() async {
          while (live.changing) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pump();
        expect(live.running, isFalse);
        expect(camera.activeStreams, 0);
        await tester.runAsync(live.start);
        await waitForFrames(tester, live);
        await tester.pump();
        expect(live.running, isTrue);
        expect(live.delegate, VisionDelegate.cpu);
      } finally {
        await tester.runAsync(() async => await controller?.close());
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        CameraPlatform.instance = original;
      }
      expect(camera.activeStreams, 0);
      expect(camera.disposed, 3);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
