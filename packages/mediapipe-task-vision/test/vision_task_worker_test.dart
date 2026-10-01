import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:mediapipe_vision/mediapipe_vision.dart';
import 'package:mediapipe_vision/src/io/gpu_frame_budget.dart';
import 'package:mediapipe_vision/src/io/vision_task_worker.dart';
import 'package:test/test.dart';

/// Options whose fake native task reports opening and closing to [events].
final class _Options extends VisionModelOptions {
  _Options(this.events, {super.delegate = VisionDelegate.cpu})
    : super(modelBytes: Uint8List(1), runningMode: RunningMode.video);
  final SendPort events;
}

/// Native tasks opened so far on this worker isolate.
var _opened = 0;

/// Answers every frame with its own number, so results show which native
/// task processed them.
final class _Native implements NativeVisionTask<int> {
  _Native(this.options) : number = ++_opened {
    options.events.send('open $number');
  }

  final _Options options;
  final int number;
  var _closed = false;

  @override
  int process(VisionTaskInput input) => number;

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    options.events.send('close $number');
  }
}

_Native _open(_Options options) => _Native(options);

/// Opens once, then fails, as a GPU that disappeared would.
_Native _openOnce(_Options options) {
  if (_opened == 1) throw const VisionTaskException('No GPU.');
  return _Native(options);
}

/// 4x4 RGBA: 64 bytes for the GPU.
final _frame = VisionImage.fromPixels(
  pixels: Uint8List(64),
  width: 4,
  height: 4,
  format: VisionPixelFormat.rgba,
);

void main() {
  late ReceivePort events;
  late List<String> log;
  setUp(() {
    events = ReceivePort();
    log = [];
    events.listen((event) => log.add(event as String));
  });
  tearDown(() => events.close());

  /// Lets the worker's last messages arrive.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('reopens the native task each time the budget is spent', () async {
    final worker = await VisionTaskWorker.create(
      _Options(events.sendPort),
      _open,
      'reopen',
      reopenAfterBytes: 128,
    );
    final answers = [
      for (var i = 0; i < 5; i++) await worker.processVideo(_frame, 0, i, null),
    ];
    await worker.dispose();
    await settle();
    expect(answers, [1, 1, 2, 2, 3]);
    expect(log, [
      'open 1',
      'close 1',
      'open 2',
      'close 2',
      'open 3',
      'close 3',
    ]);
  });

  test('keeps one native task without a budget', () async {
    final worker = await VisionTaskWorker.create(
      _Options(events.sendPort),
      _open,
      'no budget',
    );
    final answers = [
      for (var i = 0; i < 5; i++) await worker.processVideo(_frame, 0, i, null),
    ];
    await worker.dispose();
    await settle();
    expect(answers, [1, 1, 1, 1, 1]);
    expect(log, ['open 1', 'close 1']);
  });

  test('fails the task when reopening fails', () async {
    final worker = await VisionTaskWorker.create(
      _Options(events.sendPort),
      _openOnce,
      'reopen fails',
      reopenAfterBytes: 64,
    );
    expect(await worker.processVideo(_frame, 0, 0, null), 1);
    await expectLater(
      worker.processVideo(_frame, 0, 1, null),
      throwsA(
        isA<VisionTaskException>().having(
          (e) => e.message,
          'message',
          'No GPU.',
        ),
      ),
    );
    await worker.dispose();
    await settle();
    expect(log, ['open 1', 'close 1']);
  });

  group('GpuFrameBudget', () {
    test('applies to GPU tasks on macOS only', () {
      expect(
        GpuFrameBudget(
          _Options(events.sendPort, delegate: VisionDelegate.gpu),
        ).limitBytes,
        Platform.isMacOS ? 1 << 30 : isNull,
      );
      expect(GpuFrameBudget(_Options(events.sendPort)).limitBytes, isNull);
    });

    test('counts four bytes a pixel, and a 12 MP photo for a file', () {
      final budget = GpuFrameBudget(
        _Options(events.sendPort),
        limitBytes: 4000 * 3000 * 4 + 64,
      );
      expect(budget.spend(VisionImage.fromFile('photo.jpg')), isFalse);
      expect(budget.spend(_frame), isTrue);
      expect(budget.spend(_frame), isFalse);
    });
  });
}
