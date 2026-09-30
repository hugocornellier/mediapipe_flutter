import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_gallery/catalog.dart';
import 'package:mediapipe_gallery/live_page.dart';
import 'package:mediapipe_gallery/ui/components.dart';
import 'package:mediapipe_gallery/ui/speed_chart.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

import 'support/scripted_camera.dart';

const _platform = TaskPlatform(
  operatingSystem: 'macos',
  architecture: 'arm64',
  version: '15.0',
);

Future<void> _pumpLivePage(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final previous = CameraPlatform.instance;
  CameraPlatform.instance = ScriptedCamera(cameras: const []);
  addTearDown(() => CameraPlatform.instance = previous);
  final task = supportedTasks(_platform, {'face_landmarker'}, const {}).single;
  await tester.pumpWidget(
    MaterialApp(
      home: LivePage(
        task: task,
        platform: _platform,
        officialMacosLandmarkTasks: const {},
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a phone opens Output and Stats as dialogs over the feed', (
    tester,
  ) async {
    await _pumpLivePage(tester, const Size(390, 844));
    expect(find.byType(OutputCard), findsNothing);
    expect(find.byType(StatsCard), findsNothing);

    await tester.tap(find.byTooltip('Show output'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Results appear once the camera runs.'), findsOneWidget);
    await tester.tap(find.byTooltip('Close output'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);

    await tester.tap(find.byTooltip('Show stats'));
    await tester.pumpAndSettle();
    expect(find.byType(StatsCard), findsOneWidget);
    await tester.tap(find.byTooltip('Close stats'));
    await tester.pumpAndSettle();
    expect(find.byType(StatsCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide window keeps Output under the feed and Stats inline', (
    tester,
  ) async {
    await _pumpLivePage(tester, const Size(1280, 900));
    expect(find.byType(OutputCard), findsOneWidget);
    expect(find.byTooltip('Show output'), findsNothing);

    await tester.tap(find.byTooltip('Show stats'));
    await tester.pump();
    expect(find.byType(StatsCard), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
