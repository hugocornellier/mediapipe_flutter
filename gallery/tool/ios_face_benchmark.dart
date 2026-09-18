// Release-only static portrait replay. Use --mediapipe-benchmark at launch.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_flutter_vision/src/io/native_face_landmarker.dart';
import 'package:mediapipe_flutter_vision/src/io/native_frame_timings.dart';
import 'package:mediapipe_flutter_vision/src/io/native_ios_sdk.dart';

const _variant = iosImageStorageMode;
const _frames = int.fromEnvironment('BENCH_FRAMES', defaultValue: 60);
const _rounds = int.fromEnvironment('BENCH_ROUNDS', defaultValue: 3);
const _warmup = 20;
const _channel = MethodChannel('mediapipe_gallery/benchmark');
final _status = ValueNotifier('Preparing portrait replay…');

Future<Map<String, Object?>> _device() async =>
    Map<String, Object?>.from((await _channel.invokeMapMethod('deviceInfo'))!);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder(
            valueListenable: _status,
            builder: (_, value, _) => Text(value),
          ),
        ),
      ),
    ),
  );
  final report = <String, Object?>{
    'schema': 1,
    'variant': _variant,
    'frames': _frames,
    'rounds': _rounds,
    'warmup': _warmup,
    'sdk': '1.0.1',
    'workload':
        'static portrait VIDEO replay, optional outputs off, one face; '
        'public_api includes owned snapshot and worker round trip; '
        'native_profile runs separately on a worker, without frame pacing',
    'started_at': DateTime.now().toUtc().toIso8601String(),
    'runs': <Map<String, Object?>>[],
  };
  Future<void> save() async {
    await File(
      '${Directory.systemTemp.path}/gallery-ios-face-benchmark.json',
    ).writeAsString(jsonEncode(report), flush: true);
  }

  try {
    if (!Platform.isIOS) throw StateError('Physical iOS device required.');
    report['device_start'] = await _device();
    final modelData = await rootBundle.load(
      'assets/models/face_landmarker.task',
    );
    final model = modelData.buffer.asUint8List(
      modelData.offsetInBytes,
      modelData.lengthInBytes,
    );
    report['model_sha256'] = sha256.convert(model).toString();
    final photo = await rootBundle.load('assets/samples/portrait.jpg');
    final jpeg = photo.buffer.asUint8List(
      photo.offsetInBytes,
      photo.lengthInBytes,
    );
    report['photo_sha256'] = sha256.convert(jpeg).toString();
    final codec = await ui.instantiateImageCodec(jpeg);
    final source = (await codec.getNextFrame()).image;
    final fixtures = <_Fixture>[];
    for (final (width, height) in [(480, 640), (1080, 1920)]) {
      fixtures.add(await _fixture(source, width, height));
    }
    source.dispose();
    codec.dispose();
    report['fixtures'] = [
      for (final f in fixtures)
        {
          'width': f.width,
          'height': f.height,
          'stride': f.stride,
          'sha256': sha256.convert(f.pixels).toString(),
        },
    ];
    final cases = [
      for (var f = 0; f < fixtures.length; f++)
        for (final delegate in VisionDelegate.values)
          for (final paced in [false, true]) (f, delegate, paced),
    ];
    final random = math.Random(9182026);
    cases.shuffle(random);
    for (var round = 0; round < _rounds; round++) {
      final ordered = round.isEven ? cases : cases.reversed;
      for (final (index, delegate, paced) in ordered) {
        final f = fixtures[index];
        final label =
            '${f.width}x${f.height}/${delegate.name}/${paced ? "33ms" : "tight"}';
        _status.value =
            'Variant $_variant · round ${round + 1}/$_rounds\n$label';
        final before = await _device();
        final task = await FaceLandmarker.create(
          FaceLandmarkerOptions(
            modelBytes: model,
            delegate: delegate,
            runningMode: VisionRunningMode.video,
          ),
        );
        final samples = <Map<String, int>>[];
        List<double>? oracle;
        try {
          for (var i = 0; i < _warmup + _frames; i++) {
            final clock = Stopwatch()..start();
            final snapshotClock = Stopwatch()..start();
            final image = f.image();
            snapshotClock.stop();
            final result = await task.detectForVideo(
              image,
              timestampMilliseconds: i * 33,
            );
            clock.stop();
            _validate(result, f, i * 33);
            if (i >= _warmup) {
              samples.add({
                'total': clock.elapsedMicroseconds,
                'snapshot': snapshotClock.elapsedMicroseconds,
              });
              oracle ??= _coordinates(result);
            }
            if (paced) {
              final remaining = 33000 - clock.elapsedMicroseconds;
              if (remaining > 0) {
                await Future<void>.delayed(Duration(microseconds: remaining));
              }
            }
          }
        } finally {
          await task.dispose();
        }
        (report['runs'] as List).add({
          'case': '$label/public_api',
          'round': round,
          'samples_us': samples,
          'landmarks': oracle,
          'device_before': before,
          'device_after': await _device(),
        });
        await save();
        stdout.writeln(
          'IOS_FACE_BENCH ${jsonEncode({'variant': _variant, 'round': round, 'case': label, 'event': 'case_complete'})}',
        );
      }
    }
    // Separate native stage timings avoid adding stopwatches to public calls.
    for (final f in fixtures) {
      for (final delegate in VisionDelegate.values) {
        final profile = await Isolate.run(() => _profile(f, model, delegate));
        (report['runs'] as List).add(profile);
        await save();
      }
    }
    report['device_end'] = await _device();
    report['event'] = 'complete';
    report['finished_at'] = DateTime.now().toUtc().toIso8601String();
    await save();
    stdout.writeln(
      'IOS_FACE_BENCH ${jsonEncode({'variant': _variant, 'event': 'complete'})}',
    );
    exit(0);
  } catch (error, stack) {
    report['event'] = 'failed';
    report['error'] = '$error';
    await save();
    stderr.writeln(stack);
    stdout.writeln(
      'IOS_FACE_BENCH ${jsonEncode({'event': 'failed', 'error': '$error'})}',
    );
    exit(1);
  }
}

Map<String, Object?> _profile(
  _Fixture f,
  Uint8List model,
  VisionDelegate delegate,
) {
  final task = NativeFaceLandmarker(
    FaceLandmarkerOptions(
      modelBytes: model,
      delegate: delegate,
      runningMode: VisionRunningMode.video,
    ),
  );
  final image = f.image();
  final timings = NativeFrameTimings();
  final samples = <Map<String, int>>[];
  List<double>? oracle;
  try {
    for (var i = 0; i < _warmup + _frames; i++) {
      final clock = Stopwatch()..start();
      final result = task.detect(image, 0, timestamp: i * 33, timings: timings);
      clock.stop();
      _validate(result, f, i * 33);
      if (i >= _warmup) {
        samples.add({
          ...timings.microseconds,
          'total': clock.elapsedMicroseconds,
        });
        oracle ??= _coordinates(result);
      }
    }
  } finally {
    task.close();
  }
  return {
    'case': '${f.width}x${f.height}/${delegate.name}/tight/native_profile',
    'round': 0,
    'samples_us': samples,
    'landmarks': oracle,
  };
}

void _validate(FaceLandmarkerResult result, _Fixture f, int timestamp) {
  if (result.faceLandmarks.length != 1 ||
      result.faceLandmarks.single.length != 478 ||
      result.imageWidth != f.width ||
      result.imageHeight != f.height ||
      result.timestampMilliseconds != timestamp ||
      result.faceBlendshapes.isNotEmpty ||
      result.facialTransformationMatrixes.isNotEmpty ||
      result.faceLandmarks.single.any(
        (p) => !p.x.isFinite || !p.y.isFinite || !p.z.isFinite,
      )) {
    throw StateError(
      'Incorrect face result for ${f.width}x${f.height} at $timestamp.',
    );
  }
}

List<double> _coordinates(FaceLandmarkerResult result) => [
  for (final p in result.faceLandmarks.single) ...[p.x, p.y, p.z],
];

final class _Fixture {
  _Fixture(this.width, this.height, this.stride, this.pixels);
  final int width, height, stride;
  final Uint8List pixels;
  VisionImage image() => VisionImage.fromPixels(
    pixels: pixels,
    width: width,
    height: height,
    bytesPerRow: stride,
    format: VisionPixelFormat.bgra,
  );
}

Future<_Fixture> _fixture(ui.Image source, int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawColor(Colors.black, BlendMode.src);
  final scale = math.min(width / source.width, height / source.height);
  final w = source.width * scale, h = source.height * scale;
  canvas.drawImageRect(
    source,
    Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    Rect.fromLTWH((width - w) / 2, (height - h) / 2, w, h),
    Paint()..filterQuality = FilterQuality.low,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final rgba = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final stride = width * 4 + 16;
  final bgra = Uint8List(stride * height)..fillRange(0, stride * height, 0xa5);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final s = (y * width + x) * 4, d = y * stride + x * 4;
      bgra[d] = rgba[s + 2];
      bgra[d + 1] = rgba[s + 1];
      bgra[d + 2] = rgba[s];
      bgra[d + 3] = rgba[s + 3];
    }
  }
  image.dispose();
  picture.dispose();
  return _Fixture(width, height, stride, bgra);
}
