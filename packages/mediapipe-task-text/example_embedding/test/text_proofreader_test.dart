@TestOn('mac-os')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediapipe_flutter_text/text_proofreader.dart';
import 'package:mediapipe_flutter_text/src/io/third_party/mediapipe/proofreader_bindings.dart'
    as mp;
import 'package:test/test.dart';

final model = File('../models/proofread_quant_200m.litertlm').absolute.path;
final reference =
    jsonDecode(
          File(
            '../test/fixtures/proofreader/official_reference.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
final cases = (reference['cases'] as List).cast<Map<String, dynamic>>();

List<Map<String, String>> edits(List<ProofreadingCorrection> values) => [
  for (final value in values) {'type': value.type.name, 'text': value.text},
];

void compare(TextProofreaderResult result, Map<String, dynamic> entry) {
  expect(result.proofreadText, entry['result']['text'], reason: entry['name']);
  expect(edits(result.corrections), entry['result']['corrections']);
}

void compareStream(
  List<TextProofreaderUpdate> updates,
  Map<String, dynamic> entry,
) {
  expect(updates, isNotEmpty);
  expect(updates.where((e) => e.done), hasLength(1));
  expect(updates.last.done, isTrue);
  expect(updates.map((e) => e.chunk ?? '').join(), entry['result']['text']);
  expect(edits(updates.last.corrections), entry['result']['corrections']);
}

Future<TextProofreader> create([int? maxNumTokens]) => TextProofreader.create(
  TextProofreaderOptions(modelPath: model, maxNumTokens: maxNumTokens),
);

void main() {
  test('proofreader FFI sizes and field offsets match official Python ABI', () {
    final abi = reference['abi'];
    expect(
      sizeOf<mp.MpTextProofreaderOptions>(),
      abi['_MpTextProofreaderOptionsC']['size'],
    );
    expect(sizeOf<mp.MpCorrection>(), abi['_MpCorrectionC']['size']);
    expect(
      sizeOf<mp.MpTextProofreaderResult>(),
      abi['_MpTextProofreaderResultC']['size'],
    );
    expect(
      sizeOf<mp.MpTextProofreaderStreamResult>(),
      abi['_MpTextProofreaderStreamResultC']['size'],
    );
    using((arena) {
      ByteData bytes<T extends NativeType>(Pointer<T> value, int length) =>
          value.cast<Uint8>().asTypedList(length).buffer.asByteData();
      final options = arena<mp.MpTextProofreaderOptions>();
      options.ref
        ..maxNumTokens = 123
        ..cacheDir = Pointer.fromAddress(456);
      final fields = abi['_MpTextProofreaderOptionsC']['offsets'];
      final data = bytes(options, sizeOf<mp.MpTextProofreaderOptions>());
      expect(data.getInt32(fields['max_num_tokens'], Endian.host), 123);
      expect(data.getUint64(fields['cache_dir'], Endian.host), 456);
      final stream = arena<mp.MpTextProofreaderStreamResult>();
      stream.ref
        ..chunk = Pointer.fromAddress(123)
        ..correctionsCount = 7
        ..corrections = Pointer.fromAddress(456)
        ..done = true;
      final streamData = bytes(
        stream,
        sizeOf<mp.MpTextProofreaderStreamResult>(),
      );
      final offsets = abi['_MpTextProofreaderStreamResultC']['offsets'];
      expect(streamData.getUint64(offsets['chunk'], Endian.host), 123);
      expect(streamData.getInt32(offsets['corrections_count'], Endian.host), 7);
      expect(streamData.getUint64(offsets['corrections'], Endian.host), 456);
      expect(streamData.getUint8(offsets['done']), 1);
    });
  });

  for (final budget in [null, 64]) {
    test(
      'official completed and streaming results, token budget $budget',
      () async {
        final task = await create(budget);
        try {
          for (final entry in cases.where(
            (e) => e['max_num_tokens'] == budget,
          )) {
            compare(await task.proofread(entry['input']), entry);
            compareStream(
              await task.proofreadStream(entry['input']).toList(),
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

  test(
    'mixed requests serialize, disposal drains, and results remain owned',
    () async {
      final task = await create();
      final first = task.proofreadStream(cases[0]['input']).toList();
      final second = task.proofread(cases[1]['input']);
      final third = task.proofreadStream(cases[2]['input']).toList();
      final closing = task.dispose();
      expect(identical(closing, task.dispose()), isTrue);
      final updates = await first;
      final result = await second;
      final finalUpdates = await third;
      await closing;
      compareStream(updates, cases[0]);
      compare(result, cases[1]);
      compareStream(finalUpdates, cases[2]);
      expect(() => result.corrections.clear(), throwsUnsupportedError);
      expect(() => updates.last.corrections.clear(), throwsUnsupportedError);
      await expectLater(task.proofread('closed'), throwsStateError);
      expect(() => task.proofreadStream('closed'), throwsStateError);
    },
  );

  test(
    'cancelling after first chunk drains native work before next request',
    () async {
      final task = await create();
      try {
        final firstChunk = Completer<void>();
        var delivered = 0;
        final subscription = task.proofreadStream(cases[6]['input']).listen((
          _,
        ) {
          delivered++;
          if (!firstChunk.isCompleted) firstChunk.complete();
        });
        await firstChunk.future;
        final beforeCancel = delivered;
        final cancellation = subscription.cancel();
        final next = task.proofread(cases[0]['input']);
        await cancellation;
        compare(await next, cases[0]);
        expect(delivered, beforeCancel);
      } finally {
        await task.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'paused stream buffers owned results without blocking disposal',
    () async {
      final task = await create();
      final updates = <TextProofreaderUpdate>[];
      final done = Completer<void>();
      final subscription =
          task
              .proofreadStream(cases[0]['input'])
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
      compareStream(updates, cases[0]);
    },
  );

  test(
    'unlistened stream starts no work and fails if listened after disposal',
    () async {
      final task = await create();
      final stream = task.proofreadStream('She go home.');
      await task.dispose();
      await expectLater(stream.toList(), throwsStateError);
    },
  );

  test(
    'creation failures return errors instead of hanging',
    () async {
      await expectLater(
        TextProofreader.create(
          TextProofreaderOptions(modelPath: '$model.missing'),
        ),
        throwsA(isA<TextProofreaderException>()),
      );
      await expectLater(
        TextProofreader.create(
          TextProofreaderOptions(modelPath: model, delegate: TextDelegate.gpu),
        ),
        throwsA(
          isA<TextProofreaderException>().having(
            (e) => e.message,
            'message',
            contains('CPU'),
          ),
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'invalid inputs fail before native inference and leave task usable',
    () async {
      expect(() => TextProofreaderOptions(modelPath: ''), throwsArgumentError);
      expect(
        () => TextProofreaderOptions(modelPath: model, maxNumTokens: -1),
        throwsArgumentError,
      );
      expect(
        () =>
            TextProofreaderOptions(modelPath: model, maxNumTokens: 0x80000000),
        throwsArgumentError,
      );
      expect(
        () => TextProofreaderOptions(modelPath: model, cacheDirectory: ''),
        throwsArgumentError,
      );
      final task = await create();
      try {
        await expectLater(task.proofread('bad\u0000text'), throwsArgumentError);
        expect(
          () => task.proofreadStream('bad\u0000text'),
          throwsArgumentError,
        );
        compare(await task.proofread(cases[0]['input']), cases[0]);
      } finally {
        await task.dispose();
      }
    },
  );
}
