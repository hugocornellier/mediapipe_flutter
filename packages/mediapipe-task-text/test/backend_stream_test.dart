import 'dart:async';

import 'package:mediapipe_text/mediapipe_text.dart';
import 'package:mediapipe_text/platform_interface.dart';
import 'package:mediapipe_text/src/runner/text_task_runner.dart';
import 'package:test/test.dart';

/// A platform backend whose generative task is driven by the test: each
/// request completes or streams when the test says so, as Google's Android
/// SDK does from its own threads.
final class _FakeBackend implements TextTaskBackend {
  final log = <String>[];
  final pending = <Completer<Map<String, dynamic>>>[];
  final streams = <StreamController<Map<String, dynamic>>>[];
  var disposed = false;

  @override
  Future<Map<String, dynamic>> run(
    String text, [
    Map<String, Object?> arguments = const {},
  ]) {
    log.add('run $text');
    final completer = Completer<Map<String, dynamic>>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Stream<Map<String, dynamic>> stream(String text) {
    log.add('stream $text');
    final controller = StreamController<Map<String, dynamic>>();
    streams.add(controller);
    return controller.stream;
  }

  @override
  Future<void> dispose() async {
    log.add('dispose');
    disposed = true;
  }
}

void main() {
  late _FakeBackend backend;
  late BackendStreamTextTask<String, String> task;

  setUp(() async {
    backend = _FakeBackend();
    task = await BackendStreamTextTask.open(
      (name, options) async => backend,
      'text_summarizer',
      {},
      (json) => json['summary'] as String,
      (json) => json['chunk'] as String,
    );
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('requests and streams run one at a time, in submission order', () async {
    final first = task.run('one');
    final updates = task.stream('two').toList();
    final third = task.run('three');
    await settle();
    expect(backend.log, ['run one']);
    backend.pending[0].complete({'summary': 'ONE'});
    expect(await first, 'ONE');
    await settle();
    expect(backend.log, ['run one', 'stream two']);
    backend.streams[0]
      ..add({'chunk': 'a', 'done': false})
      ..add({'chunk': 'b', 'done': true});
    await backend.streams[0].close();
    expect(await updates, ['a', 'b']);
    await settle();
    expect(backend.log, ['run one', 'stream two', 'run three']);
    backend.pending[1].complete({'summary': 'THREE'});
    expect(await third, 'THREE');
  });

  test(
    "cancelling stops delivery and waits for Google's last update",
    () async {
      final delivered = <String>[];
      final subscription = task.stream('long').listen(delivered.add);
      await settle();
      backend.streams[0].add({'chunk': 'a', 'done': false});
      await settle();
      expect(delivered, ['a']);
      var cancelled = false;
      final cancelling = subscription.cancel().then((_) => cancelled = true);
      final next = task.run('after');
      await settle();
      // Google is still generating: the next request waits, as does cancel.
      expect(cancelled, isFalse);
      expect(backend.log, ['stream long']);
      backend.streams[0].add({'chunk': 'b', 'done': true});
      await backend.streams[0].close();
      await cancelling;
      expect(delivered, ['a']);
      await settle();
      expect(backend.log, ['stream long', 'run after']);
      backend.pending[0].complete({'summary': 'AFTER'});
      expect(await next, 'AFTER');
    },
  );

  test('a paused stream buffers updates without blocking disposal', () async {
    final updates = <String>[];
    final done = Completer<void>();
    final subscription =
        task.stream('text').listen(updates.add, onDone: done.complete)..pause();
    await settle();
    backend.streams[0].add({'chunk': 'a', 'done': true});
    await backend.streams[0].close();
    final closing = task.dispose();
    await settle();
    expect(backend.disposed, isTrue);
    expect(updates, isEmpty);
    subscription.resume();
    await done.future;
    await closing;
    expect(updates, ['a']);
  });

  test("Google's failure ends the stream as a TaskException", () async {
    final updates = task.stream('text').toList();
    await settle();
    backend.streams[0].addError(StateError('model failed'));
    await backend.streams[0].close();
    await expectLater(
      updates,
      throwsA(
        isA<TaskException>().having(
          (e) => e.message,
          'message',
          contains('model failed'),
        ),
      ),
    );
    // The task stays usable afterwards.
    final next = task.run('after');
    await settle();
    backend.pending[0].complete({'summary': 'AFTER'});
    expect(await next, 'AFTER');
  });

  test('after disposal, requests fail and an unlistened stream starts no '
      'work', () async {
    final stream = task.stream('never');
    await task.dispose();
    await task.dispose();
    expect(backend.log, ['dispose']);
    await expectLater(task.run('closed'), throwsStateError);
    await expectLater(stream.toList(), throwsStateError);
    expect(backend.log, ['dispose']);
  });

  test('the backend refuses a cache directory on Android before opening', () {
    textTaskBackendFactory = (name, options) async => backend;
    addTearDown(() => textTaskBackendFactory = null);
    expect(
      () => openGenerativeTextTask<String, String, TextSummarizerOptions>(
        TextSummarizerOptions(modelPath: 'model', cacheDirectory: '/cache'),
        capabilities: () async => textSummarizerCapabilitiesForPlatform(
          const TaskPlatform(operatingSystem: 'android', architecture: 'arm64'),
        ),
        task: 'text_summarizer',
        settings: const {},
        cacheDirectory: '/cache',
        decodeResult: (json) => '',
        decodeUpdate: (json) => '',
        native: (options) async => throw UnimplementedError(),
      ),
      throwsA(
        isA<RuntimeUnavailableException>().having(
          (e) => e.fix,
          'fix',
          contains('cacheDirectory'),
        ),
      ),
    );
    expect(backend.log, isEmpty);
  });
}
