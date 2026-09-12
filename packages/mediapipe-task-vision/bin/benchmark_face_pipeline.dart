import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_flutter_vision/src/io/native_face_landmarker.dart';
import 'package:mediapipe_flutter_vision/src/io/native_frame_timings.dart';

// Run the AOT bundle from the package root. Output contains raw samples and
// provenance; a separate summary is convenient to review without decompressing.
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.length > 3) {
    throw ArgumentError(
      'Usage: benchmark_face_pipeline OUTPUT [FRAMES] [ROUNDS]',
    );
  }
  final output = arguments[0];
  final frames = arguments.length > 1 ? int.parse(arguments[1]) : 150;
  final rounds = arguments.length > 2 ? int.parse(arguments[2]) : 3;
  if (frames < 50 || rounds < 2) {
    throw ArgumentError('Use at least 50 measured frames and two rounds.');
  }
  if (File('$output.json.gz').existsSync() ||
      File('$output.summary.json').existsSync()) {
    throw StateError('Refusing to overwrite an existing run: $output');
  }
  const warmup = 30;
  const seed = 478;
  const specs = [
    _Input(640, 480, VisionPixelFormat.bgra),
    _Input(1280, 720, VisionPixelFormat.bgra),
    _Input(1920, 1080, VisionPixelFormat.bgra),
    _Input(1920, 1080, VisionPixelFormat.rgba),
  ];
  final cases = [
    for (final spec in specs)
      for (final delegate in VisionDelegate.values)
        for (final direct in [false, true])
          (spec: spec, delegate: delegate, direct: direct),
  ]..shuffle(math.Random(seed));
  final metadata = _metadata(frames, rounds, warmup, seed);
  final runs = <Map<String, Object>>[];
  for (var round = 0; round < rounds; round++) {
    // Reverse the whole seeded order on alternating rounds, including paths.
    for (final entry in round.isEven ? cases : cases.reversed) {
      final label =
          '${entry.spec.name}/${entry.delegate.name}/'
          '${entry.direct ? 'native_stages' : 'public_api'}';
      stderr.writeln('Round ${round + 1}/$rounds: $label');
      final run = entry.direct
          ? await Isolate.run(
              () => _native(entry.spec, entry.delegate, frames, warmup),
            )
          : await _public(entry.spec, entry.delegate, frames, warmup);
      runs.add({'round': round + 1, 'case': label, ...run});
    }
  }
  final report = {
    'metadata': metadata,
    'finished_utc': DateTime.now().toUtc().toIso8601String(),
    'thermal_after': _command('pmset', ['-g', 'therm']),
    'runs': runs,
  };
  File('$output.json.gz')
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(gzip.encode(utf8.encode(jsonEncode(report))));
  final summary = {
    ...report,
    'raw_sha256': _hash('$output.json.gz'),
    'runs': [
      for (final run in runs) {...run}..remove('samples_us'),
    ],
  };
  File('$output.summary.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(summary)}\n',
  );
  stdout.writeln('Saved $output.json.gz and $output.summary.json');
}

const _model = 'models/face_landmarker.task';
const _portrait = 'test/fixtures/face_detection/portrait-301x209.rgb';

final class _Input {
  const _Input(this.width, this.height, this.format);
  final int width;
  final int height;
  final VisionPixelFormat format;
  int get stride => width * 4 + 64;
  String get name => '${width}x${height}_${format.name}_pad64';

  Uint8List pixels() {
    final rgb = File(_portrait).readAsBytesSync();
    final pixels = Uint8List(stride * height);
    final scale = math.min(width / 301, height / 209);
    final scaledWidth = (301 * scale).floor();
    final scaledHeight = (209 * scale).floor();
    final left = (width - scaledWidth) ~/ 2;
    final top = (height - scaledHeight) ~/ 2;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final target = y * stride + x * 4;
        pixels[target + 3] = 255;
        if (x < left ||
            x >= left + scaledWidth ||
            y < top ||
            y >= top + scaledHeight) {
          continue;
        }
        final source =
            (((y - top) * 209 ~/ scaledHeight) * 301 +
                ((x - left) * 301 ~/ scaledWidth)) *
            3;
        pixels[target] =
            rgb[source + (format == VisionPixelFormat.bgra ? 2 : 0)];
        pixels[target + 1] = rgb[source + 1];
        pixels[target + 2] =
            rgb[source + (format == VisionPixelFormat.bgra ? 0 : 2)];
      }
    }
    return pixels;
  }

  VisionImage image(Uint8List pixels) => VisionImage.fromPixels(
    pixels: pixels,
    width: width,
    height: height,
    bytesPerRow: stride,
    format: format,
  );
}

FaceLandmarkerOptions _options(VisionDelegate delegate) =>
    FaceLandmarkerOptions(
      modelPath: _model,
      runningMode: VisionRunningMode.video,
      delegate: delegate,
    );

Future<Map<String, Object>> _public(
  _Input spec,
  VisionDelegate delegate,
  int frames,
  int warmup,
) async {
  final pixels = spec.pixels();
  final startup = Stopwatch()..start();
  final task = await FaceLandmarker.create(_options(delegate));
  startup.stop();
  final samples = <Map<String, int>>[];
  try {
    for (var i = 0; i < frames + warmup; i++) {
      final timer = Stopwatch()..start();
      final image = spec.image(pixels);
      final snapshot = timer.elapsedMicroseconds;
      final result = await task.detectForVideo(
        image,
        timestampMilliseconds: i * 33,
      );
      final total = timer.elapsedMicroseconds;
      timer.stop();
      _validate(result, i * 33);
      if (i >= warmup) {
        samples.add({
          'snapshot': snapshot,
          'request_roundtrip': total - snapshot,
          'total': total,
        });
      }
    }
  } finally {
    await task.dispose();
  }
  return _runResult(samples, startup.elapsedMicroseconds);
}

Map<String, Object> _native(
  _Input spec,
  VisionDelegate delegate,
  int frames,
  int warmup,
) {
  // A persistent synchronous task on its own isolate, with the same input.
  // This is a separate experiment; do not subtract it from public percentiles
  // and call the difference isolate latency.
  final pixels = spec.pixels();
  final startup = Stopwatch()..start();
  final task = NativeFaceLandmarker(_options(delegate));
  startup.stop();
  final timings = NativeFrameTimings();
  final samples = <Map<String, int>>[];
  try {
    for (var i = 0; i < frames + warmup; i++) {
      final timer = Stopwatch()..start();
      final image = spec.image(pixels);
      final snapshot = timer.elapsedMicroseconds;
      final result = task.detect(image, 0, timestamp: i * 33, timings: timings);
      final total = timer.elapsedMicroseconds;
      timer.stop();
      _validate(result, i * 33);
      if (i >= warmup) {
        samples.add({
          'snapshot': snapshot,
          ...timings.microseconds,
          'total': total,
        });
      }
    }
  } finally {
    task.close();
  }
  return _runResult(samples, startup.elapsedMicroseconds);
}

void _validate(FaceLandmarkerResult result, int timestamp) {
  if (result.timestampMilliseconds != timestamp ||
      result.faceLandmarks.length != 1 ||
      result.faceLandmarks.single.length != 478 ||
      result.faceBlendshapes.isNotEmpty ||
      result.facialTransformationMatrixes.isNotEmpty ||
      result.faceLandmarks.single.any(
        (p) => !p.x.isFinite || !p.y.isFinite || !p.z.isFinite,
      )) {
    throw StateError('Invalid benchmark result at $timestamp ms.');
  }
}

Map<String, Object> _runResult(List<Map<String, int>> samples, int startup) => {
  'create_us': startup,
  'samples_us': samples,
  'stages_ms': {
    for (final stage in samples.first.keys)
      stage: _stats([for (final sample in samples) sample[stage]! / 1000]),
  },
};

Map<String, double> _stats(List<double> values) {
  values.sort();
  final mean = values.reduce((a, b) => a + b) / values.length;
  double percentile(double p) => values[(p * values.length).ceil() - 1];
  return {
    'mean': mean,
    'p50': percentile(.5),
    'p95': percentile(.95),
    'p99': percentile(.99),
    'min': values.first,
    'max': values.last,
    'stddev': math.sqrt(
      values.fold<double>(0, (s, x) => s + (x - mean) * (x - mean)) /
          values.length,
    ),
  };
}

String _command(String executable, List<String> arguments) {
  final result = Process.runSync(executable, arguments);
  return result.exitCode == 0 ? '${result.stdout}'.trim() : 'unavailable';
}

String _hash(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

Map<String, Object> _metadata(int frames, int rounds, int warmup, int seed) {
  final bundle = File(Platform.resolvedExecutable).parent.parent;
  return {
    'schema': 1,
    'started_utc': DateTime.now().toUtc().toIso8601String(),
    'git_head_at_run': _command('git', ['rev-parse', 'HEAD']),
    'git_status_at_run': _command('git', ['status', '--porcelain']),
    'executable_sha256': _hash(Platform.resolvedExecutable),
    'dart': Platform.version,
    'os': Platform.operatingSystemVersion,
    'hardware': _command('sysctl', [
      '-n',
      'hw.model',
      'machdep.cpu.brand_string',
      'hw.memsize',
      'hw.logicalcpu',
    ]),
    'thermal_before': _command('pmset', ['-g', 'therm']),
    'camera_process': _command('pgrep', ['-x', 'mediapipe_face_camera']),
    'model_sha256': _hash(_model),
    'fixture_sha256': _hash(_portrait),
    'libraries_sha256': {
      for (final file in Directory(
        '${bundle.path}/lib',
      ).listSync().whereType<File>())
        file.uri.pathSegments.last: _hash(file.path),
    },
    'frames': frames,
    'rounds': rounds,
    'warmup_frames': warmup,
    'order_seed': seed,
    'workload':
        'Static portrait, nearest-neighbour letterbox, VIDEO, one face, '
        '33ms timestamps, no pacing, blendshapes/matrices off. '
        'Camera capture/rendering excluded; native stages include CPU and GPU synchronization.',
  };
}
