// Release-only face-landmarker replay for the image-storage audit.
//
// Launch with --mediapipe-benchmark --bench-token=<id> [--bench-settle=<s>]
// [--bench-validate]. Frames come from pre-rendered BGRA assets whose SHA-256
// is compiled in, so every launch replays identical bytes. The public cases
// and native-stage profiles match the earlier ios_face_benchmark.dart design,
// except that native profiles now run in every round, interleaved with the
// public cases. This file imports only APIs that exist both before and after
// the storage change, so baseline and candidate apps build from one source.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_flutter_vision/src/io/native_face_landmarker.dart';
import 'package:mediapipe_flutter_vision/src/io/native_frame_timings.dart';
import 'package:mediapipe_flutter_vision/src/io/native_ios_sdk.dart'
    show hasOfficialIosFaceRuntime;

const _artifact = String.fromEnvironment('BENCH_ARTIFACT', defaultValue: '?');
const _storageDefine = String.fromEnvironment(
  'MEDIAPIPE_IOS_IMAGE_STORAGE',
  defaultValue: 'unset',
);
const _frames = 60;
const _rounds = 3;
const _warmup = 20;
const _period = 33000;
const _fixtureSpecs = [
  (
    480,
    640,
    1936,
    'assets/bench/portrait_480x640_bgra.bin',
    'ff4ec3d50a0a04c57c8f0cc4e87458c6920f0dffe03265b92b1de0b8765b4d7c',
  ),
  (
    1080,
    1920,
    4336,
    'assets/bench/portrait_1080x1920_bgra.bin',
    'ed31c24aa39df247449716a4d993f44cc37e3611426bd3e652049a6d1c21cd8f',
  ),
];
const _channel = MethodChannel('mediapipe_gallery/benchmark');
final _status = ValueNotifier('Preparing storage audit…');

Future<Map<String, Object?>> _device() async {
  final info = Map<String, Object?>.from(
    (await _channel.invokeMapMethod('deviceInfo'))!,
  );
  info['rss_bytes'] = ProcessInfo.currentRss;
  info['at'] = DateTime.now().toUtc().toIso8601String();
  return info;
}

String? _argument(List<Object?> arguments, String name) {
  for (final value in arguments) {
    if (value is String && value.startsWith('--$name=')) {
      return value.substring(name.length + 3);
    }
  }
  return null;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder(
            valueListenable: _status,
            builder: (_, value, _) => Text(value, textAlign: TextAlign.center),
          ),
        ),
      ),
    ),
  );
  final start = await _device();
  final arguments = (start['arguments'] as List?) ?? const [];
  final token = _argument(arguments, 'bench-token') ?? 'none';
  final settle = int.tryParse(_argument(arguments, 'bench-settle') ?? '') ?? 0;
  final validate = arguments.contains('--bench-validate');
  final report = <String, Object?>{
    'schema': 2,
    'harness': 'storage-audit-1',
    'artifact': _artifact,
    'storage_define': _storageDefine,
    'platform': Platform.operatingSystem,
    'token': token,
    'mode': validate ? 'validate' : 'timed',
    'frames': _frames,
    'rounds': _rounds,
    'warmup': _warmup,
    'period_us': _period,
    'settle_s': settle,
    'sdk': Platform.isIOS ? 'ios-tasks-1.0.1' : 'official-macos-1.0.0',
    'started_at': DateTime.now().toUtc().toIso8601String(),
    'device_start': start,
    'runs': <Map<String, Object?>>[],
  };
  final output = File(
    '${Directory.systemTemp.path}/storage-audit-$token.json',
  );
  Future<void> save() => output.writeAsString(jsonEncode(report), flush: true);
  stdout.writeln('STORAGE_AUDIT_REPORT ${output.path}');

  try {
    final modelData = await rootBundle.load(
      'assets/models/face_landmarker.task',
    );
    final model = Uint8List.fromList(
      modelData.buffer.asUint8List(
        modelData.offsetInBytes,
        modelData.lengthInBytes,
      ),
    );
    report['model_sha256'] = sha256.convert(model).toString();
    final fixtures = <_Fixture>[];
    for (final (width, height, stride, asset, expected) in _fixtureSpecs) {
      final data = await rootBundle.load(asset);
      final pixels = Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final digest = sha256.convert(pixels).toString();
      if (digest != expected || pixels.length != stride * height) {
        throw StateError('Fixture bytes changed: $asset $digest');
      }
      fixtures.add(_Fixture(width, height, stride, pixels, digest));
    }
    report['fixtures'] = [for (final f in fixtures) f.describe()];
    report['official_ios_runtime'] = hasOfficialIosFaceRuntime();
    if (settle > 0) {
      _status.value = '$_artifact · settling ${settle}s';
      await Future<void>.delayed(Duration(seconds: settle));
    }
    report['device_after_settle'] = await _device();
    await save();
    if (validate) {
      await _validation(report, fixtures, model, save);
    } else {
      await _timed(report, fixtures, model, save);
    }
    report['device_end'] = await _device();
    report['event'] = 'complete';
    report['finished_at'] = DateTime.now().toUtc().toIso8601String();
    await save();
    stdout.writeln(
      'STORAGE_AUDIT ${jsonEncode({'artifact': _artifact, 'token': token, 'event': 'complete'})}',
    );
    exit(0);
  } catch (error, stack) {
    report['event'] = 'failed';
    report['error'] = '$error';
    report['finished_at'] = DateTime.now().toUtc().toIso8601String();
    await save();
    stderr.writeln(stack);
    stdout.writeln(
      'STORAGE_AUDIT ${jsonEncode({'artifact': _artifact, 'token': token, 'event': 'failed', 'error': '$error'})}',
    );
    exit(1);
  }
}

Future<void> _timed(
  Map<String, Object?> report,
  List<_Fixture> fixtures,
  Uint8List model,
  Future<void> Function() save,
) async {
  final cases = [
    for (var f = 0; f < fixtures.length; f++)
      for (final delegate in VisionDelegate.values)
        for (final kind in ['tight', 'paced', 'native']) (f, delegate, kind),
  ];
  cases.shuffle(math.Random(9182026));
  var order = 0;
  for (var round = 0; round < _rounds; round++) {
    final ordered = round.isEven ? cases : cases.reversed;
    for (final (index, delegate, kind) in ordered) {
      final f = fixtures[index];
      final label = '${f.width}x${f.height}/${delegate.name}';
      _status.value = '$_artifact · round ${round + 1}/$_rounds\n$label/$kind';
      final before = await _device();
      final wallStart = DateTime.now().toUtc().toIso8601String();
      final Map<String, Object?> run;
      if (kind == 'native') {
        run = await Isolate.run(() => _profile(f, model, delegate));
        run['case'] = '$label/tight/native_profile';
      } else {
        run = await _public(f, model, delegate, paced: kind == 'paced');
        run['case'] = '$label/${kind == 'paced' ? '33ms' : 'tight'}/public_api';
      }
      run['round'] = round;
      run['order'] = order++;
      run['wall_start'] = wallStart;
      run['device_before'] = before;
      run['device_after'] = await _device();
      (report['runs'] as List).add(run);
      await save();
    }
  }
}

Future<Map<String, Object?>> _public(
  _Fixture f,
  Uint8List model,
  VisionDelegate delegate, {
  required bool paced,
}) async {
  final task = await FaceLandmarker.create(
    FaceLandmarkerOptions(
      modelBytes: model,
      delegate: delegate,
      runningMode: VisionRunningMode.video,
    ),
  );
  final samples = <Map<String, int>>[];
  final outputs = _Outputs();
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
        outputs.add(result);
      }
      if (paced) {
        final remaining = _period - clock.elapsedMicroseconds;
        if (remaining > 0) {
          await Future<void>.delayed(Duration(microseconds: remaining));
        }
      }
    }
  } finally {
    await task.dispose();
  }
  return {'samples_us': samples, ...outputs.describe()};
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
  final outputs = _Outputs();
  try {
    for (var i = 0; i < _warmup + _frames; i++) {
      final clock = Stopwatch()..start();
      final result = task.detect(image, 0, timestamp: i * 33, timings: timings);
      clock.stop();
      _validate(result, f, i * 33);
      if (i >= _warmup) {
        samples.add({...timings.microseconds, 'total': clock.elapsedMicroseconds});
        outputs.add(result);
      }
    }
  } finally {
    task.close();
  }
  return {'samples_us': samples, ...outputs.describe()};
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

/// Every landmark of every measured frame, digested outside the timed region.
final class _Outputs {
  final _frames = <Float32List>[];

  void add(FaceLandmarkerResult result) => _frames.add(_landmarks(result));

  Map<String, Object?> describe() {
    final all = BytesBuilder(copy: false);
    for (final frame in _frames) {
      all.add(frame.buffer.asUint8List());
    }
    return {
      'landmarks': [..._frames.first],
      'landmarks_last': [..._frames.last],
      'landmarks_sequence_sha256': sha256.convert(all.takeBytes()).toString(),
      'distinct_frame_outputs': {
        for (final frame in _frames)
          sha256.convert(frame.buffer.asUint8List()).toString(),
      }.length,
    };
  }
}

/// Face count plus every coordinate; native values are C floats, so float32
/// storage is exact.
Float32List _landmarks(FaceLandmarkerResult result) {
  final faces = result.faceLandmarks;
  final values = Float32List(
    1 + faces.fold<int>(0, (n, f) => n + f.length * 3),
  );
  values[0] = faces.length.toDouble();
  var i = 1;
  for (final face in faces) {
    for (final p in face) {
      values[i++] = p.x;
      values[i++] = p.y;
      values[i++] = p.z;
    }
  }
  return values;
}

String _digest(FaceLandmarkerResult result) =>
    sha256.convert(_landmarks(result).buffer.asUint8List()).toString();

/// Untimed correctness checks, compared across artifacts by the analysis.
Future<void> _validation(
  Map<String, Object?> report,
  List<_Fixture> fixtures,
  Uint8List model,
  Future<void> Function() save,
) async {
  final small = fixtures[0], large = fixtures[1];
  final blankSmall = _Fixture.blank(small.width, small.height, small.stride);
  final blankLarge = _Fixture.blank(large.width, large.height, large.stride);
  // Odd width: Core Video pads rows, so stale pooled padding must not matter.
  final odd = small.crop(1, 1, 477, 637, 477 * 4 + 12);
  final checks = <String, Object?>{};
  report['validation'] = checks;
  for (final delegate in VisionDelegate.values) {
    final name = delegate.name;
    _status.value = '$_artifact · validating $name';
    // Fresh IMAGE-mode references, one task per input.
    final reference = <String, String>{};
    for (final (key, f) in [
      ('face480', small),
      ('face1080', large),
      ('odd477', odd),
      ('blank480', blankSmall),
      ('blank1080', blankLarge),
    ]) {
      final task = await _create(model, delegate, VisionRunningMode.image);
      try {
        final result = await task.detectImage(f.image());
        _expectFaces(result, key.startsWith('blank') ? 0 : 1, f);
        reference[key] = _digest(result);
      } finally {
        await task.dispose();
      }
    }
    checks['$name/reference'] = reference;
    // Strides: identical pixels at three row pitches must match exactly.
    final strides = <String, Object?>{};
    for (final (key, f) in [('face480', small), ('face1080', large)]) {
      final task = await _create(model, delegate, VisionRunningMode.image);
      try {
        for (final pad in [0, 16, 256]) {
          final restrided = f.restride(f.width * 4 + pad);
          final digest = _digest(await task.detectImage(restrided.image()));
          strides['$key/+$pad'] = digest == reference[key];
        }
      } finally {
        await task.dispose();
      }
    }
    checks['$name/strides_match_reference'] = strides;
    // One IMAGE task across size changes and face/blank alternation.
    final sequence = [
      ('face480', small),
      ('blank480', blankSmall),
      ('face1080', large),
      ('blank1080', blankLarge),
      ('face480', small),
      ('odd477', odd),
      ('face1080', large),
      ('blank480', blankSmall),
      ('face480', small),
      ('blank1080', blankLarge),
      ('face1080', large),
      ('odd477', odd),
      ('blank480', blankSmall),
    ];
    final imageTask = await _create(model, delegate, VisionRunningMode.image);
    final alternation = <Object?>[];
    try {
      for (var repeat = 0; repeat < 3; repeat++) {
        for (final (key, f) in sequence) {
          final result = await imageTask.detectImage(f.image());
          _expectFaces(result, key.startsWith('blank') ? 0 : 1, f);
          alternation.add(_digest(result) == reference[key]);
        }
      }
    } finally {
      await imageTask.dispose();
    }
    checks['$name/image_alternation_matches_reference'] = alternation;
    // VIDEO mode keeps tracking state, so its sequence is compared across apps.
    final videoTask = await _create(model, delegate, VisionRunningMode.video);
    final video = <String>[];
    var timestamp = 0;
    try {
      for (final (key, f, count) in [
        ('face480', small, 4),
        ('face1080', large, 4),
        ('blank1080', blankLarge, 2),
        ('face1080', large, 3),
        ('face480', small, 3),
        ('blank480', blankSmall, 2),
        ('odd477', odd, 3),
        ('face480', small, 3),
      ]) {
        for (var i = 0; i < count; i++) {
          final result = await videoTask.detectForVideo(
            f.image(),
            timestampMilliseconds: timestamp += 33,
          );
          _expectFaces(result, key.startsWith('blank') ? 0 : 1, f);
          video.add('$key:${_digest(result)}');
        }
      }
    } finally {
      await videoTask.dispose();
    }
    checks['$name/video_sequence'] = video;
    // Lifecycle: repeated create/detect/dispose at both sizes.
    final rss = <int>[];
    for (var cycle = 0; cycle < 12; cycle++) {
      final task = await _create(model, delegate, VisionRunningMode.video);
      for (var i = 0; i < 10; i++) {
        final f = i.isEven ? large : small;
        _expectFaces(
          await task.detectForVideo(f.image(), timestampMilliseconds: i * 33),
          1,
          f,
        );
      }
      await task.dispose();
      await task.dispose();
      Object? after;
      try {
        await task.detectForVideo(small.image(), timestampMilliseconds: 999);
      } catch (error) {
        after = error;
      }
      if (after is! StateError) {
        throw StateError('Detect after dispose did not fail: $after');
      }
      rss.add(ProcessInfo.currentRss);
    }
    checks['$name/lifecycle_rss_bytes'] = rss;
    // Direct native owner, closed twice, as the worker does on shutdown.
    final native = NativeFaceLandmarker(
      FaceLandmarkerOptions(
        modelBytes: model,
        delegate: delegate,
        runningMode: VisionRunningMode.video,
      ),
    );
    _expectFaces(native.detect(large.image(), 0, timestamp: 0), 1, large);
    _expectFaces(native.detect(small.image(), 0, timestamp: 33), 1, small);
    native
      ..close()
      ..close();
    checks['$name/native_double_close'] = true;
    await save();
  }
  checks['leftover_model_files'] = Directory.systemTemp
      .listSync()
      .where((e) => e.path.split('/').last.startsWith('mediapipe-'))
      .map((e) => e.path.split('/').last)
      .toList();
}

Future<FaceLandmarker> _create(
  Uint8List model,
  VisionDelegate delegate,
  VisionRunningMode mode,
) => FaceLandmarker.create(
  FaceLandmarkerOptions(
    modelBytes: model,
    delegate: delegate,
    runningMode: mode,
  ),
);

void _expectFaces(FaceLandmarkerResult result, int faces, _Fixture f) {
  if (result.faceLandmarks.length != faces ||
      result.imageWidth != f.width ||
      result.imageHeight != f.height ||
      result.faceLandmarks.any((face) => face.length != 478)) {
    throw StateError(
      'Expected $faces face(s) at ${f.width}x${f.height}, '
      'got ${result.faceLandmarks.length}.',
    );
  }
}

final class _Fixture {
  _Fixture(this.width, this.height, this.stride, this.pixels, this.sha);

  factory _Fixture.blank(int width, int height, int stride) {
    final pixels = Uint8List(stride * height)..fillRange(0, stride * height, 0xa5);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final d = y * stride + x * 4;
        pixels[d] = pixels[d + 1] = pixels[d + 2] = 0x80;
        pixels[d + 3] = 0xff;
      }
    }
    return _Fixture(width, height, stride, pixels, sha256.convert(pixels).toString());
  }

  final int width, height, stride;
  final Uint8List pixels;
  final String sha;

  VisionImage image() => VisionImage.fromPixels(
    pixels: pixels,
    width: width,
    height: height,
    bytesPerRow: stride,
    format: VisionPixelFormat.bgra,
  );

  /// Same visible pixels at another row pitch, padding filled with 0x5a.
  _Fixture restride(int pitch) {
    final out = Uint8List(pitch * height)..fillRange(0, pitch * height, 0x5a);
    for (var y = 0; y < height; y++) {
      out.setRange(y * pitch, y * pitch + width * 4, pixels, y * stride);
    }
    return _Fixture(width, height, pitch, out, sha256.convert(out).toString());
  }

  _Fixture crop(int left, int top, int w, int h, int pitch) {
    final out = Uint8List(pitch * h)..fillRange(0, pitch * h, 0x3c);
    for (var y = 0; y < h; y++) {
      final source = (top + y) * stride + left * 4;
      out.setRange(y * pitch, y * pitch + w * 4, pixels, source);
    }
    return _Fixture(w, h, pitch, out, sha256.convert(out).toString());
  }

  Map<String, Object?> describe() => {
    'width': width,
    'height': height,
    'stride': stride,
    'sha256': sha,
  };
}
