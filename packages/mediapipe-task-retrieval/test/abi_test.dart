@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:mediapipe_retrieval/src/io/third_party/mediapipe/retrieval_bindings.dart'
    as mp;
import 'package:test/test.dart';

/// The struct sizes Google's Python ctypes declare, recorded with the
/// reference answers (tool/generate_reference.py).
final _sizes =
    (jsonDecode(
              File(
                'test/fixtures/embedding_gemma_2_text_vision_reference.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>)['structSizes']!
        as Map<String, Object?>;

void main() {
  final dart = <String, int>{
    'MpUniversalEmbedderOptions': sizeOf<mp.MpUniversalEmbedderOptions>(),
    'MpBaseOptions': sizeOf<mp.MpBaseOptions>(),
    'MpKeyValuePair': sizeOf<mp.MpKeyValuePair>(),
    'MpSemanticRetrieverOptions': sizeOf<mp.MpSemanticRetrieverOptions>(),
    'MpRetrievalRecord': sizeOf<mp.MpRetrievalRecord>(),
    'MpRetrievalResult': sizeOf<mp.MpRetrievalResult>(),
    'MpRecordIdsResult': sizeOf<mp.MpRecordIdsResult>(),
    'MpTextPart': sizeOf<mp.MpTextPart>(),
    'MpImagePart': sizeOf<mp.MpImagePart>(),
    'MpAudioPart': sizeOf<mp.MpAudioPart>(),
    'MpTaskPart': sizeOf<mp.MpTaskPart>(),
  };
  for (final MapEntry(key: name, value: size) in _sizes.entries) {
    test('$name is laid out as Google\'s Python declares it', () {
      expect(dart[name], size, reason: name);
    });
  }
  test('every bound struct is checked', () {
    expect(dart.keys.toSet(), _sizes.keys.toSet());
  });
}
