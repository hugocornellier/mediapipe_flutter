import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:web/web.dart' as web;

@JS('mediapipeApiTestReport')
external set _report(JSObject value);

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> rejects(Future<Object?> Function() action, Type type) async {
  try {
    await action();
  } catch (error) {
    require(
      error.runtimeType == type || type == Object,
      'Expected $type, got $error',
    );
    return;
  }
  throw StateError('Expected $type');
}

Map<String, Object?> copied(FaceLandmarkerResult result) => {
  'width': result.imageWidth,
  'height': result.imageHeight,
  'landmarks': [
    for (final p in result.faceLandmarks.single) [p.x, p.y, p.z],
  ],
  'blendshapes': [for (final c in result.faceBlendshapes.single) c.score],
  'matrix': result.facialTransformationMatrixes.single.values,
};

Future<Map<String, Object?>> checkApi() async {
  final delegate = Uri.base.queryParameters['delegate'] == 'gpu'
      ? VisionDelegate.gpu
      : VisionDelegate.cpu;
  final data = await rootBundle.load('assets/models/face_landmarker.task');
  final sourceModel = Uint8List.fromList(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  final options = FaceLandmarkerOptions(
    delegate: delegate,
    modelBytes: sourceModel,
    outputFaceBlendshapes: true,
    outputFacialTransformationMatrixes: true,
  );
  final modelFirstByte = sourceModel.first;
  sourceModel.fillRange(0, sourceModel.length, 0);
  require(
    options.modelBytes!.first == modelFirstByte,
    'Model input was not copied',
  );
  final portrait = Uri.base
      .resolve('assets/assets/samples/portrait.jpg')
      .toString();
  final image = VisionImage.fromFile(portrait);
  final task = await FaceLandmarker.create(options);
  final checks = <String>[];
  late FaceLandmarkerResult original;
  try {
    require(
      options.modelBytes!.first == modelFirstByte,
      'Model buffer detached',
    );
    original = await task.detectImage(image);
    require(
      original.faceLandmarks.single.length == 478,
      'Expected 478 landmarks',
    );
    require(
      original.faceBlendshapes.single.length == 52,
      'Expected 52 blendshapes',
    );
    require(
      original.facialTransformationMatrixes.single.values.length == 16,
      'Expected 4x4 matrix',
    );
    checks.add('official-image-landmarks-blendshapes-matrix');
    final response = await web.window.fetch(portrait.toJS).toDart;
    final bitmap = await web.window
        .createImageBitmap(await response.blob().toDart)
        .toDart;
    final canvas = web.OffscreenCanvas(bitmap.width, bitmap.height);
    final context =
        canvas.getContext('2d')! as web.OffscreenCanvasRenderingContext2D;
    context.drawImage(bitmap, 0, 0);
    bitmap.close();
    final rgba = context
        .getImageData(0, 0, canvas.width, canvas.height)
        .data
        .toDart;
    for (final format in VisionPixelFormat.values) {
      final stride = canvas.width * format.channels + 16;
      final pixels = Uint8List(stride * canvas.height);
      for (var y = 0; y < canvas.height; y++) {
        for (var x = 0; x < canvas.width; x++) {
          final from = (y * canvas.width + x) * 4;
          final to = y * stride + x * format.channels;
          pixels[to] = rgba[from + (format == VisionPixelFormat.bgra ? 2 : 0)];
          pixels[to + 1] = rgba[from + 1];
          pixels[to + 2] =
              rgba[from + (format == VisionPixelFormat.bgra ? 0 : 2)];
          if (format.channels == 4) pixels[to + 3] = 255;
        }
      }
      final frame = VisionImage.fromPixels(
        pixels: pixels,
        width: canvas.width,
        height: canvas.height,
        format: format,
        bytesPerRow: stride,
      );
      pixels.fillRange(0, pixels.length, 0);
      final result = await task.detectImage(frame);
      require(
        result.faceLandmarks.single.length == 478,
        'Pixel inference failed',
      );
      for (var i = 0; i < 478; i++) {
        require(
          (result.faceLandmarks.single[i].x -
                      original.faceLandmarks.single[i].x)
                  .abs() <
              1e-5,
          'Padded ${format.name} changed x coordinate',
        );
        require(
          (result.faceLandmarks.single[i].y -
                      original.faceLandmarks.single[i].y)
                  .abs() <
              1e-5,
          'Padded ${format.name} changed y coordinate',
        );
      }
    }
    checks.add('copied-padded-rgb-rgba-bgra');
    for (final rotation in [0, 90, 180, 270, -90, 360, -360, 450]) {
      final result = await task.detectImage(image, rotationDegrees: rotation);
      require(
        result.imageWidth == original.imageWidth &&
            result.imageHeight == original.imageHeight,
        'Rotation changed input coordinate dimensions',
      );
      require(
        result.faceLandmarks
            .expand((f) => f)
            .every((p) => p.x.isFinite && p.y.isFinite && p.z.isFinite),
        'Invalid rotation result',
      );
    }
    checks.add('all-four-rotations');
    await rejects(
      () => task.detectImage(image, rotationDegrees: 45),
      ArgumentError,
    );
    await rejects(
      () => task.detectForVideo(image, timestampMilliseconds: 1),
      StateError,
    );
  } finally {
    await task.dispose();
  }
  await task.dispose();
  await rejects(() => task.detectImage(image), StateError);
  require(
    original.faceLandmarks.single.length == 478,
    'Results invalid after disposal',
  );
  checks.add('owned-results-mode-validation-idempotent-disposal');
  final video = await FaceLandmarker.create(
    FaceLandmarkerOptions(
      delegate: delegate,
      modelBytes: options.modelBytes,
      runningMode: VisionRunningMode.video,
    ),
  );
  try {
    final frames = await Future.wait([
      for (final t in [1, 2, 3])
        video.detectForVideo(image, timestampMilliseconds: t),
    ]);
    require(
      frames.every((r) => r.faceLandmarks.single.length == 478),
      'Queued VIDEO failed',
    );
    require(
      frames[0].timestampMilliseconds == 1 &&
          frames[2].timestampMilliseconds == 3,
      'Wrong timestamps',
    );
    await rejects(
      () => video.detectForVideo(image, timestampMilliseconds: 3),
      ArgumentError,
    );
    await rejects(
      () => video.detectForVideo(
        VisionImage.fromFile('missing.jpg'),
        timestampMilliseconds: 4,
      ),
      FaceLandmarkerException,
    );
    await rejects(
      () => video.detectForVideo(image, timestampMilliseconds: 4),
      ArgumentError,
    );
    final recovery = video.detectForVideo(image, timestampMilliseconds: 5);
    await video.dispose();
    require(
      (await recovery).faceLandmarks.single.length == 478,
      'Dispose lost pending result',
    );
    checks.add('video-queue-timestamps-failed-frame-recovery-disposal');
  } finally {
    await video.dispose();
  }
  await rejects(
    () => FaceLandmarker.create(
      FaceLandmarkerOptions(modelBytes: Uint8List.fromList([1])),
    ),
    FaceLandmarkerException,
  );
  checks.add('invalid-model-explicit-error');
  return {'status': 'passed', 'checks': checks, 'image': copied(original)};
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Map<String, Object?> report;
  try {
    report = await checkApi();
  } catch (error, stack) {
    report = {'status': 'failed', 'error': '$error', 'stack': '$stack'};
  }
  _report = report.jsify()! as JSObject;
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(child: Text('API checks: ${report['status']}')),
      ),
    ),
  );
}
