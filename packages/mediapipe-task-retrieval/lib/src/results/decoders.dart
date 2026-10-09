/// Results from the JSON-like maps both runtimes answer in: Google's
/// JavaScript result objects in browsers, and the same shapes, with typed
/// data, from the native worker.
library;

import 'dart:typed_data';

import 'package:mediapipe_core/mediapipe_core.dart';

import '../types/results.dart';

/// A [UniversalEmbedderResult] from `{embeddings: [{floatEmbedding,
/// quantizedEmbedding, headIndex, headName}]}`.
UniversalEmbedderResult decodeEmbedderResult(Object? json) {
  final map = json! as Map;
  return UniversalEmbedderResult(
    embeddings: [
      for (final raw in map['embeddings']! as List) _embedding(raw as Map),
    ],
  );
}

Embedding _embedding(Map map) {
  final floats = _floats(map['floatEmbedding']);
  final quantized = _bytes(map['quantizedEmbedding']);
  if ((floats == null) == (quantized == null)) {
    throw const TaskException('MediaPipe returned an invalid embedding.');
  }
  final name = map['headName'] as String?;
  return Embedding(
    floatEmbedding: floats,
    quantizedEmbedding: quantized,
    headIndex: (map['headIndex'] as num?)?.toInt() ?? 0,
    headName: name == null || name.isEmpty ? null : name,
  );
}

/// Google's browser API leaves the unused representation empty or absent.
Float32List? _floats(Object? value) => switch (value) {
  null => null,
  Float32List list => list.isEmpty ? null : list,
  List list =>
    list.isEmpty
        ? null
        : Float32List.fromList([for (final v in list) (v as num).toDouble()]),
  _ => throw TaskException('MediaPipe returned an invalid embedding: $value'),
};

Uint8List? _bytes(Object? value) => switch (value) {
  null => null,
  Uint8List list => list.isEmpty ? null : list,
  List list =>
    list.isEmpty
        ? null
        : Uint8List.fromList([for (final v in list) (v as num).toInt()]),
  _ => throw TaskException('MediaPipe returned an invalid embedding: $value'),
};

/// A [RetrievalResult] from `{records: [{id, text, score, metadata}]}`.
RetrievalResult decodeRetrievalResult(Object? json) {
  final map = json! as Map;
  return RetrievalResult(
    records: [
      for (final raw in map['records']! as List)
        RetrievalRecord(
          id: (raw as Map)['id']! as String,
          text: raw['text'] as String? ?? '',
          score: (raw['score']! as num).toDouble(),
          metadata: ((raw['metadata'] as Map?) ?? const {}).map(
            (key, value) => MapEntry(key as String, '$value'),
          ),
        ),
    ],
  );
}

/// The ids from `{ids: [...]}`.
List<String> decodeRecordIds(Object? json) =>
    ((json! as Map)['ids']! as List).cast<String>();
