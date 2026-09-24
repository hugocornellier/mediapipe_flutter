@TestOn('mac-os')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediapipe_flutter_text/text_summarizer.dart';
import 'package:mediapipe_flutter_text/src/io/third_party/mediapipe/summarizer_bindings.dart'
    as mp;
import 'package:test/test.dart';

final model = File(
  '../models/summarization_quant_200m_2modes.litertlm',
).absolute.path;
final reference =
    jsonDecode(
          File(
            '../test/fixtures/summarizer/official_reference.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
final cases = (reference['cases'] as List).cast<Map<String, dynamic>>();

TextSummarizerMode modeFor(Map<String, dynamic> entry) =>
    entry['mode'] == 'TLDR'
    ? TextSummarizerMode.tldr
    : TextSummarizerMode.keypoints;

void compare(TextSummarizerResult result, Map<String, dynamic> entry) =>
    expect(result.summary, entry['result']['summary'], reason: entry['name']);

void compareStream(
  List<TextSummarizerUpdate> updates,
  Map<String, dynamic> entry,
) {
  expect(updates, isNotEmpty);
  expect(updates.where((e) => e.done), hasLength(1));
  expect(updates.last.done, isTrue);
  expect(updates.map((e) => e.chunk ?? '').join(), entry['result']['summary']);
}

Future<TextSummarizer> create([
  TextSummarizerMode mode = TextSummarizerMode.keypoints,
  int? budget,
]) => TextSummarizer.create(
  TextSummarizerOptions(modelPath: model, mode: mode, maxNumTokens: budget),
);

void main() {
  test('FFI sizes and field offsets match the official Python ABI', () {
    final abi = reference['abi'];
    expect(
      sizeOf<mp.MpTextSummarizerOptions>(),
      abi['_MpTextSummarizerOptionsC']['size'],
    );
    expect(
      sizeOf<mp.MpTextSummarizerResult>(),
      abi['_MpTextSummarizerResultC']['size'],
    );
    expect(
      sizeOf<mp.MpTextSummarizerStreamResult>(),
      abi['_MpTextSummarizerStreamResultC']['size'],
    );
    using((arena) {
      final options = arena<mp.MpTextSummarizerOptions>();
      options.ref
        ..mode = 1
        ..maxNumTokens = 64
        ..cacheDir = Pointer.fromAddress(1234);
      final bytes = options
          .cast<Uint8>()
          .asTypedList(sizeOf<mp.MpTextSummarizerOptions>())
          .buffer
          .asByteData();
      final fields = abi['_MpTextSummarizerOptionsC']['offsets'];
      expect(bytes.getInt32(fields['mode'], Endian.host), 1);
      expect(bytes.getInt32(fields['max_num_tokens'], Endian.host), 64);
      expect(bytes.getUint64(fields['cache_dir'], Endian.host), 1234);
      final stream = arena<mp.MpTextSummarizerStreamResult>();
      stream.ref
        ..chunk = Pointer.fromAddress(5678)
        ..done = true;
      final data = stream
          .cast<Uint8>()
          .asTypedList(sizeOf<mp.MpTextSummarizerStreamResult>())
          .buffer
          .asByteData();
      final offsets = abi['_MpTextSummarizerStreamResultC']['offsets'];
      expect(data.getUint64(offsets['chunk'], Endian.host), 5678);
      expect(data.getUint8(offsets['done']), 1);
    });
  });

  for (final mode in TextSummarizerMode.values) {
    for (final budget in [null, 64]) {
      test(
        'official completed/streaming summaries: ${mode.name}, budget $budget',
        () async {
          final task = await create(mode, budget);
          try {
            expect(task.mode, mode);
            expect(task.delegate, TextDelegate.cpu);
            for (final entry in cases.where(
              (e) => modeFor(e) == mode && e['max_num_tokens'] == budget,
            )) {
              compare(await task.summarize(entry['input']), entry);
              compareStream(
                await task.summarizeStream(entry['input']).toList(),
                entry,
              );
            }
          } finally {
            await task.dispose();
          }
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }

    test('native empty-input errors preserve the task: ${mode.name}', () async {
      final task = await create(mode);
      try {
        final entry = (reference['errors'] as List).singleWhere(
          (e) => e['mode'] == mode.name.toUpperCase(),
        );
        final error = isA<TextSummarizerException>().having(
          (e) => e.message,
          'message',
          entry['message'],
        );
        await expectLater(task.summarize(''), throwsA(error));
        await expectLater(task.summarizeStream('').toList(), throwsA(error));
        final valid = cases.firstWhere((e) => modeFor(e) == mode);
        compare(await task.summarize(valid['input']), valid);
        compareStream(
          await task.summarizeStream(valid['input']).toList(),
          valid,
        );
      } finally {
        await task.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 20)));
  }

  test(
    'mixed queued requests and both modes own results after disposal',
    () async {
      final tldr = await create(TextSummarizerMode.tldr);
      final keypoints = await create();
      final paragraph = cases.first;
      final bullets = cases.firstWhere(
        (e) => modeFor(e) == TextSummarizerMode.keypoints,
      );
      final first = tldr.summarizeStream(paragraph['input']).toList();
      final second = tldr.summarize(cases[1]['input']);
      final third = keypoints.summarize(bullets['input']);
      final closing = tldr.dispose();
      expect(identical(closing, tldr.dispose()), isTrue);
      final updates = await first;
      final result = await second;
      final otherMode = await third;
      await closing;
      await keypoints.dispose();
      compareStream(updates, paragraph);
      compare(result, cases[1]);
      compare(otherMode, bullets);
      await expectLater(tldr.summarize('closed'), throwsStateError);
      expect(() => tldr.summarizeStream('closed'), throwsStateError);
    },
  );

  test('cancellation drains and the next request succeeds', () async {
    final task = await create(TextSummarizerMode.tldr);
    try {
      final first = Completer<void>();
      var delivered = 0;
      final subscription = task.summarizeStream(cases.first['input']).listen((
        _,
      ) {
        delivered++;
        if (!first.isCompleted) first.complete();
      });
      await first.future;
      final before = delivered;
      final cancelling = subscription.cancel();
      final next = task.summarize(cases[1]['input']);
      await cancelling;
      compare(await next, cases[1]);
      expect(delivered, before);
    } finally {
      await task.dispose();
    }
  });

  test(
    'paused streams do not block disposal; unlistened streams start no work',
    () async {
      final task = await create(TextSummarizerMode.tldr);
      final lazy = task.summarizeStream(cases[1]['input']);
      final updates = <TextSummarizerUpdate>[];
      final done = Completer<void>();
      final subscription =
          task
              .summarizeStream(cases.first['input'])
              .listen(
                updates.add,
                onDone: done.complete,
                onError: done.completeError,
              )
            ..pause();
      await task.dispose();
      expect(updates, isEmpty);
      subscription.resume();
      await done.future;
      compareStream(updates, cases.first);
      await expectLater(lazy.toList(), throwsStateError);
    },
  );

  test('zero budget, native cache and default mode preserve output', () async {
    final cache = Directory('../build/summarizer-cache')
      ..createSync(recursive: true);
    final task = await TextSummarizer.create(
      TextSummarizerOptions(
        modelPath: model,
        maxNumTokens: 0,
        cacheDirectory: cache.absolute.path,
      ),
    );
    try {
      expect(task.mode, TextSummarizerMode.keypoints);
      final entry = cases.firstWhere((e) => modeFor(e) == task.mode);
      compare(await task.summarize(entry['input']), entry);
    } finally {
      await task.dispose();
    }
  });

  test('creation errors propagate without hanging', () async {
    await expectLater(
      TextSummarizer.create(TextSummarizerOptions(modelPath: '$model.missing')),
      throwsA(isA<TextSummarizerException>()),
    );
    await expectLater(
      TextSummarizer.create(
        TextSummarizerOptions(modelPath: model, delegate: TextDelegate.gpu),
      ),
      throwsA(
        isA<TextSummarizerException>().having(
          (e) => e.message,
          'message',
          contains('CPU'),
        ),
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('invalid Dart inputs leave the task usable', () async {
    expect(() => TextSummarizerOptions(modelPath: ''), throwsArgumentError);
    expect(
      () => TextSummarizerOptions(modelPath: model, maxNumTokens: -1),
      throwsArgumentError,
    );
    expect(
      () => TextSummarizerOptions(modelPath: model, maxNumTokens: 0x80000000),
      throwsArgumentError,
    );
    expect(
      () => TextSummarizerOptions(modelPath: model, cacheDirectory: ''),
      throwsArgumentError,
    );
    final task = await create(TextSummarizerMode.tldr);
    try {
      await expectLater(task.summarize('bad\u0000text'), throwsArgumentError);
      expect(() => task.summarizeStream('bad\u0000text'), throwsArgumentError);
      compare(await task.summarize(cases.first['input']), cases.first);
    } finally {
      await task.dispose();
    }
  });
}
