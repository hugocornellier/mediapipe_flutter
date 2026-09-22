import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_gallery/live/live_camera_controller.dart';
import 'package:mediapipe_gallery/live/live_camera_view.dart';
import 'package:mediapipe_gallery/main.dart';

import 'support/alignment_oracle.dart';

// A real camera must be in front of this test, showing a face. On hosted
// Linux that is a v4l2loopback device fed by ffmpeg, on hosted Windows a Media
// Foundation virtual camera (tool/windows/vcam); on a phone it is you.
// Nothing is replaced: the platform camera plugin, the gallery, the
// controller, the worker and Google's task all run as shipped.
//
// The overlay-alignment oracle needs a screenshot that includes the camera
// preview texture. Android and iOS take one natively through integration_test;
// Linux under Xvfb grabs the X root window and Windows copies the desktop,
// both after calibrating where the Flutter view sits on the screen with a
// solid-colour frame. macOS records capture and face counts and skips the
// oracle.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real camera: capture, face in view, overlay alignment, stop/start',
    (tester) async {
      final report = <String, Object?>{
        'platform': Platform.operatingSystem,
        'started': DateTime.now().toUtc().toIso8601String(),
      };
      final screenshots = _Screenshots(binding);
      Rect? viewOnScreen;
      var pixelsPerLogical = tester.view.devicePixelRatio;
      LiveCameraController<Object?>? controller;
      try {
        if (screenshots.calibrates) {
          // Locate the Flutter view on the screen before the gallery opens.
          const marker = Color(0xFFFF00FF);
          await tester.pumpWidget(const ColoredBox(color: marker));
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 700)),
          );
          final shot = (await tester.runAsync(screenshots.take))!;
          viewOnScreen = boundsOfColor(shot, marker);
          report['screen_size'] = [shot.width, shot.height];
          expect(viewOnScreen, isNotNull, reason: 'Flutter view not on screen');
          final logical =
              tester.view.physicalSize / tester.view.devicePixelRatio;
          pixelsPerLogical = viewOnScreen!.width / logical.width;
          report['view_on_screen'] = [
            viewOnScreen.left,
            viewOnScreen.top,
            viewOnScreen.width,
            viewOnScreen.height,
          ];
          report['pixels_per_logical'] = pixelsPerLogical;
        }

        final cameras = await tester.runAsync(availableCameras);
        report['cameras'] = [
          for (final camera in cameras!)
            {
              'name': camera.name,
              'lens': camera.lensDirection.name,
              'sensor_orientation': camera.sensorOrientation,
            },
        ];
        expect(cameras, isNotEmpty, reason: 'this test needs a real camera');

        await tester.pumpWidget(const GalleryApp());
        for (
          var i = 0;
          i < 100 && find.text('Live Face Landmarker').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
        }
        expect(find.text('Live Face Landmarker'), findsOneWidget);
        await tester.tap(find.text('Live Face Landmarker'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        controller = tester
            .widget<LiveCameraView>(find.byType(LiveCameraView))
            .controller;
        final live = controller;

        // Phase 1: real capture with a face in view.
        final first = await _faceFrames(tester, live);
        report['first_session'] = first;
        expect(live.error, isNull);
        expect(first['face_frames'], greaterThanOrEqualTo(10));

        // Phase 2: overlay alignment against the on-screen preview.
        if (screenshots.available) {
          await tester.tap(find.byTooltip('Connections'));
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 400)),
          );
          await tester.pump();
          final face =
              (live.result! as FaceLandmarkerResult).faceLandmarks.single;
          final geometry = overlayGeometry(tester, live);
          final shot = await tester.runAsync(screenshots.take);
          final origin = viewOnScreen?.topLeft ?? Offset.zero;
          final previewOnScreen = Rect.fromLTWH(
            origin.dx + geometry.box.left * pixelsPerLogical,
            origin.dy + geometry.box.top * pixelsPerLogical,
            geometry.box.width * pixelsPerLogical,
            geometry.box.height * pixelsPerLogical,
          );
          final model = await tester.runAsync(
            () => rootBundle.load('assets/models/face_landmarker.task'),
          );
          final measurement = await tester.runAsync(
            () => measureAlignment(
              screenshot: shot!,
              previewInScreenshot: previewOnScreen,
              pixelsPerLogical: pixelsPerLogical,
              liveFace: face,
              transform: geometry.transform,
              modelBytes: model!.buffer.asUint8List(
                model.offsetInBytes,
                model.lengthInBytes,
              ),
            ),
          );
          report['alignment'] = {
            ...measurement!.toJson(),
            'overlay_box_logical': [
              geometry.box.left,
              geometry.box.top,
              geometry.box.width,
              geometry.box.height,
            ],
            'frame_size': [live.frameSize!.width, live.frameSize!.height],
            'frame_rotation': live.frameRotationDegrees,
            'mirror': geometry.transform.mirror,
          };
          await screenshots.keep(shot!, 'preview-without-overlay');
          await tester.tap(find.byTooltip('Connections'));
          await tester.pump();
          expect(
            measurement.observedFaces,
            1,
            reason: 'the on-screen preview must show one face',
          );
          final verdict =
              'median ${measurement.median.toStringAsFixed(4)}, max '
              '${measurement.maximum.toStringAsFixed(4)}; the mirrored '
              'hypothesis scores ${measurement.medianIfMirrored.toStringAsFixed(4)}';
          expect(
            measurement.median,
            lessThanOrEqualTo(alignmentTolerance),
            reason: 'overlay is off the on-screen face: $verdict',
          );
          expect(
            measurement.maximum,
            lessThanOrEqualTo(alignmentOutlierTolerance),
            reason: 'one probe is far off the on-screen face: $verdict',
          );
        } else {
          report['alignment'] = 'no screenshot transport on this platform';
        }

        // Phase 3: stop, restart, and confirm the camera is really released.
        await tester.tap(find.text('Stop camera'));
        await tester.pump();
        await tester.runAsync(() async {
          while (live.changing) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pump();
        expect(live.running, isFalse);
        await tester.tap(find.text('Start camera'));
        await tester.pump();
        final second = await _faceFrames(tester, live);
        report['second_session'] = second;
        expect(live.running, isTrue);
        expect(second['face_frames'], greaterThanOrEqualTo(10));
      } catch (error) {
        // The record says why it failed; the test still fails.
        report['error'] = '$error';
        rethrow;
      } finally {
        await tester.runAsync(() async => await controller?.close());
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        report['finished'] = DateTime.now().toUtc().toIso8601String();
        await tester.runAsync(() => _writeReport(binding, report));
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

/// Pumps until the live controller has processed enough frames with a face.
Future<Map<String, Object?>> _faceFrames(
  WidgetTester tester,
  LiveCameraController<Object?> controller,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  var faceFrames = 0, lastCounted = 0;
  while ((controller.changing || faceFrames < 12) &&
      controller.error == null &&
      DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 33));
    final result = controller.result;
    if (controller.processedFrames != lastCounted &&
        result is FaceLandmarkerResult &&
        result.faceLandmarks.isNotEmpty) {
      lastCounted = controller.processedFrames;
      faceFrames++;
    }
  }
  final result = controller.result;
  return {
    'camera': controller.description?.name,
    'delegate': controller.delegate.name,
    'processed_frames': controller.processedFrames,
    'skipped_frames': controller.skippedFrames,
    'face_frames': faceFrames,
    'landmarks':
        result is FaceLandmarkerResult && result.faceLandmarks.isNotEmpty
        ? result.faceLandmarks.first.length
        : 0,
    'frame_size': controller.frameSize == null
        ? null
        : [controller.frameSize!.width, controller.frameSize!.height],
    'frame_rotation': controller.frameRotationDegrees,
    'average_inference_ms': controller.averageInferenceMilliseconds,
    'average_frame_ms': controller.averageFrameMilliseconds,
    'error': controller.error,
  };
}

Future<void> _writeReport(
  IntegrationTestWidgetsFlutterBinding binding,
  Map<String, Object?> report,
) async {
  binding.reportData = {...?binding.reportData, 'real_camera': report};
  // The console line is the record of last resort: sandboxed macOS and iOS
  // apps cannot write outside their container, so print before writing.
  // ignore: avoid_print
  print('REAL_CAMERA ${jsonEncode(report)}');
  final path = Platform.environment['MEDIAPIPE_CAMERA_REPORT'];
  if (path == null) return;
  final json = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
  try {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(json);
  } on FileSystemException catch (error) {
    final fallback = File(
      '${Directory.systemTemp.path}/real-camera-report.json',
    );
    await fallback.writeAsString(json);
    // ignore: avoid_print
    print(
      'REAL_CAMERA_REPORT_PATH ${fallback.path} (requested $path: '
      '${error.osError?.message ?? error.message})',
    );
  }
}

/// Where a screenshot that includes the camera texture can come from.
final class _Screenshots {
  _Screenshots(this.binding);
  final IntegrationTestWidgetsFlutterBinding binding;

  /// Linux under X11 grabs the root window and Windows the desktop, so both
  /// calibrate the view's position first.
  bool get calibrates =>
      (Platform.isLinux && Platform.environment['DISPLAY'] != null) ||
      Platform.isWindows;

  bool get available => calibrates || Platform.isAndroid || Platform.isIOS;

  Future<RgbaImage> take() async {
    if (calibrates) {
      final path =
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'real-camera-${DateTime.now().microsecondsSinceEpoch}.png';
      final grab = Platform.isWindows
          ? await Process.run('powershell', [
              '-NoProfile',
              '-NonInteractive',
              '-Command',
              _windowsScreenshot(path),
            ])
          : await Process.run('import', [
              '-window',
              'root',
              '-depth',
              '8',
              'png:$path',
            ]);
      if (grab.exitCode != 0) {
        throw StateError('screenshot failed: ${grab.stderr}');
      }
      final bytes = await File(path).readAsBytes();
      await File(path).delete();
      return decodeImage(bytes);
    }
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    final bytes = await binding.takeScreenshot('real-camera');
    return decodeImage(Uint8List.fromList(bytes));
  }

  /// Retains a screenshot next to the report when a directory is configured.
  Future<void> keep(RgbaImage image, String name) async {
    final path = Platform.environment['MEDIAPIPE_CAMERA_REPORT'];
    if (path == null) return;
    // Raw RGBA plus dimensions: no encoder dependency, and small enough.
    final target = File('${File(path).parent.path}/$name.rgba');
    await target.parent.create(recursive: true);
    await target.writeAsBytes(image.rgba);
    await File('${target.path}.json').writeAsString(
      '${jsonEncode({'width': image.width, 'height': image.height})}\n',
    );
  }
}

/// PowerShell that copies the primary screen to [path] as a PNG with GDI+.
/// The process declares itself DPI aware first, so a scaled display is
/// captured in physical pixels, the space the calibration frame is found in.
String _windowsScreenshot(String path) => [
  'Add-Type -AssemblyName System.Windows.Forms, System.Drawing',
  "Add-Type -Namespace Native -Name Dpi -MemberDefinition '"
      '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
      "'",
  '[Native.Dpi]::SetProcessDPIAware() | Out-Null',
  r'$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds',
  r'$bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height',
  r'$graphics = [System.Drawing.Graphics]::FromImage($bitmap)',
  r'$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)',
  "\$bitmap.Save('${path.replaceAll("'", "''")}', "
      '[System.Drawing.Imaging.ImageFormat]::Png)',
].join('\n');
