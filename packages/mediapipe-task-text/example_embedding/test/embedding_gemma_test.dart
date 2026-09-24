@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediapipe_flutter_text/mediapipe_flutter_text.dart';
import 'package:mediapipe_flutter_text/src/io/third_party/mediapipe/embedding_gemma_bindings.dart'
    as mp;
import 'package:test/test.dart';

final model = File('../models/embedding_gemma.task').absolute.path;
final reference =
    jsonDecode(
          File(
            '../test/fixtures/embedding_gemma/official_reference.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
final cases = (reference['cases'] as List).cast<Map<String, dynamic>>();

TextFormatContext? contextFor(Map<String, dynamic> entry) {
  final context = entry['context'] as Map<String, dynamic>?;
  if (context == null) return null;
  const types = [
    'RETRIEVAL_QUERY',
    'RETRIEVAL_DOCUMENT',
    'SEMANTIC_SIMILARITY',
    'CLASSIFICATION',
    'CLUSTERING',
    'QUESTION_ANSWERING',
    'FACT_CHECKING',
    'CODE_RETRIEVAL',
  ];
  return TextFormatContext(
    taskType: EmbeddingTaskType.values[types.indexOf(context['task_type'])],
    title: context['title'],
    role: context['role'] == 'DOCUMENT' ? TextRole.document : TextRole.query,
  );
}

void compare(TextEmbeddingResult result, Map<String, dynamic> entry) {
  final expected = entry['embeddings'] as List;
  expect(result.embeddings, hasLength(expected.length));
  // The library stamps each request; Google's Python ctypes misread it as
  // absent (see tool/official_embedding_layout.py).
  expect(result.timestampMs, isNotNull);
  for (var i = 0; i < expected.length; i++) {
    final embedding = result.embeddings[i];
    expect(embedding.headIndex, expected[i]['head_index']);
    expect(embedding.headName, expected[i]['head_name']);
    expect(embedding.dimensions, 768);
    final values = expected[i]['values'] as List;
    if (entry['quantize'] == true) {
      expect(embedding.floatValues, isNull);
      expect(embedding.quantizedValues, values);
    } else {
      expect(embedding.quantizedValues, isNull);
      for (var j = 0; j < values.length; j++) {
        expect(
          embedding.floatValues![j],
          closeTo((values[j] as num).toDouble(), 1e-6),
          reason: '${entry['name']} head $i value $j',
        );
      }
    }
  }
}

void main() {
  test('FFI layout matches the official Python 1.0.1 ABI', () {
    final abi = reference['abi'] as Map<String, dynamic>;
    expect(sizeOf<mp.MpBaseOptions>(), abi['MpBaseOptionsC']['size']);
    expect(sizeOf<mp.MpEmbedderOptions>(), abi['_MpEmbedderOptionsC']['size']);
    expect(
      sizeOf<mp.MpTextEmbedderOptions>(),
      abi['_MpTextEmbedderOptionsC']['size'],
    );
    expect(
      sizeOf<mp.MpTextFormatContext>(),
      abi['_MpTextFormatContextC']['size'],
    );
    expect(sizeOf<mp.MpEmbedding>(), abi['MpEmbeddingC']['size']);
    expect(sizeOf<mp.MpEmbeddingResult>(), abi['MpEmbeddingResultC']['size']);
    using((arena) {
      final options = arena<mp.MpTextEmbedderOptions>();
      options.ref.baseOptions
        ..fileDescriptor = -1
        ..hostSystem = 2
        ..modelAssetBufferCount = 0x12345678;
      final data = options
          .cast<Uint8>()
          .asTypedList(sizeOf<mp.MpTextEmbedderOptions>())
          .buffer
          .asByteData();
      final offsets = abi['MpBaseOptionsC']['offsets'];
      expect(data.getInt32(offsets['file_descriptor'], Endian.host), -1);
      expect(data.getInt32(offsets['host_system'], Endian.host), 2);
      expect(
        data.getUint32(offsets['model_asset_buffer_count'], Endian.host),
        0x12345678,
      );
      final format = arena<mp.MpTextFormatContext>();
      format.ref
        ..taskType = 8
        ..role = 2
        ..title = Pointer.fromAddress(1234);
      final bytes = format
          .cast<Uint8>()
          .asTypedList(sizeOf<mp.MpTextFormatContext>())
          .buffer
          .asByteData();
      final fields = abi['_MpTextFormatContextC']['offsets'];
      expect(bytes.getInt32(fields['task_type'], Endian.host), 8);
      expect(bytes.getInt32(fields['role'], Endian.host), 2);
      expect(bytes.getUint64(fields['title'], Endian.host), 1234);
    });
  });

  for (final quantize in [false, true]) {
    test('official CPU reference embeddings, quantize=$quantize', () async {
      final task = await EmbeddingGemma.create(
        EmbeddingGemmaOptions(
          modelPath: model,
          quantize: quantize,
          l2Normalize: quantize,
        ),
      );
      try {
        for (final entry in cases.where(
          (entry) => entry['quantize'] == quantize,
        )) {
          compare(
            await task.embed(entry['text'], context: contextFor(entry)),
            entry,
          );
        }
      } finally {
        await task.dispose();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  }

  test(
    'concurrent requests keep their own results; disposal drains the queue',
    () async {
      final task = await EmbeddingGemma.create(
        EmbeddingGemmaOptions(modelPath: model),
      );
      final selected = cases.sublist(1, 4);
      final pending = [
        for (final entry in selected)
          task.embed(entry['text'], context: contextFor(entry)),
      ];
      final closing = task.dispose();
      final results = await Future.wait(pending);
      await closing;
      await task.dispose();
      for (var i = 0; i < selected.length; i++) {
        compare(results[i], selected[i]);
      }
      final cat = results[0].embeddings.single;
      final related = TextEmbedding.cosineSimilarity(
        cat,
        results[1].embeddings.single,
      );
      final unrelated = TextEmbedding.cosineSimilarity(
        cat,
        results[2].embeddings.single,
      );
      expect(related, greaterThan(unrelated));
      expect(TextEmbedding.cosineSimilarity(cat, cat), closeTo(1, 1e-12));
      expect(() => cat.floatValues![0] = 0, throwsUnsupportedError);
      await expectLater(task.embed('closed'), throwsStateError);
    },
  );

  test('buffer model produces the same official embedding', () async {
    final task = await EmbeddingGemma.create(
      EmbeddingGemmaOptions(modelBytes: await File(model).readAsBytes()),
    );
    try {
      compare(await task.embed(cases.first['text']), cases.first);
    } finally {
      await task.dispose();
    }
  });

  test('creation errors propagate instead of hanging the worker', () async {
    await expectLater(
      EmbeddingGemma.create(EmbeddingGemmaOptions(modelPath: '$model.missing')),
      throwsA(isA<EmbeddingGemmaException>()),
    );
    await expectLater(
      EmbeddingGemma.create(
        EmbeddingGemmaOptions(modelBytes: Uint8List.fromList([1, 2, 3])),
      ),
      throwsA(isA<EmbeddingGemmaException>()),
    );
    await expectLater(
      EmbeddingGemma.create(
        EmbeddingGemmaOptions(modelPath: model, delegate: TextDelegate.gpu),
      ),
      throwsA(
        isA<EmbeddingGemmaException>().having(
          (e) => e.message,
          'message',
          contains('CPU'),
        ),
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('invalid Dart inputs are rejected without poisoning the task', () async {
    expect(() => EmbeddingGemmaOptions(), throwsArgumentError);
    expect(() => EmbeddingGemmaOptions(modelPath: ''), throwsArgumentError);
    expect(
      () => EmbeddingGemmaOptions(modelPath: model, modelBytes: Uint8List(1)),
      throwsArgumentError,
    );
    expect(
      () => TextFormatContext(
        taskType: EmbeddingTaskType.retrievalDocument,
        title: 'bad\u0000title',
      ),
      throwsArgumentError,
    );
    final task = await EmbeddingGemma.create(
      EmbeddingGemmaOptions(modelPath: model),
    );
    try {
      await expectLater(task.embed('bad\u0000text'), throwsArgumentError);
      compare(await task.embed(cases.first['text']), cases.first);
    } finally {
      await task.dispose();
    }
  });

  test('cosine uses signed quantized bytes and validates vector types', () {
    TextEmbedding q(List<int> values) => TextEmbedding(
      quantizedValues: Uint8List.fromList(values),
      headIndex: 0,
    );
    expect(
      TextEmbedding.cosineSimilarity(q([127, 128]), q([128, 127])),
      lessThan(-.99),
    );
    expect(
      () => TextEmbedding.cosineSimilarity(q([0]), q([1])),
      throwsArgumentError,
    );
    expect(
      () => TextEmbedding.cosineSimilarity(q([1]), q([1, 2])),
      throwsArgumentError,
    );
    expect(
      () => TextEmbedding.cosineSimilarity(
        q([1]),
        TextEmbedding(floatValues: Float32List.fromList([1]), headIndex: 0),
      ),
      throwsArgumentError,
    );
  });

  test(
    'official token-limit failures propagate through inference and close',
    () async {
      final task = await EmbeddingGemma.create(
        EmbeddingGemmaOptions(modelPath: model),
      );
      await expectLater(
        task.embed(
          List.filled(160, 'A cat sleeps peacefully. ').join(),
          context: TextFormatContext(
            taskType: EmbeddingTaskType.semanticSimilarity,
          ),
        ),
        throwsA(
          isA<EmbeddingGemmaException>().having(
            (e) => e.message,
            'message',
            contains('too long'),
          ),
        ),
      );
      await expectLater(
        task.embed('The graph has already failed.'),
        throwsA(isA<EmbeddingGemmaException>()),
      );
      final closing = task.dispose();
      expect(identical(closing, task.dispose()), isTrue);
      await expectLater(closing, throwsA(isA<EmbeddingGemmaException>()));
      await expectLater(task.embed('closed'), throwsStateError);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}
