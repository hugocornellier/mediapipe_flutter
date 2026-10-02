/// One decoder from the platform SDK adapters' results to the Dart types.
///
/// Google's browser runtime and its Android SDK both deliver Audio Classifier
/// results as JSON in the shape of Google's JavaScript API: one
/// classification result per chunk. The adapters only forward them.
library;

import 'package:mediapipe_core/mediapipe_core.dart';

import 'types.dart';

/// Decodes the per-chunk results of one clip.
List<AudioClassifierResult> decodeAudioClassifierResults(List<Object?> json) =>
    [
      for (final chunk in json.cast<Map>())
        AudioClassifierResult(
          timestampMilliseconds: (chunk['timestampMs'] as num?)?.toInt() ?? 0,
          classifications: [
            for (final head
                in (chunk['classifications'] as List? ?? const []).cast<Map>())
              Classifications(
                categories: [
                  for (final value in (head['categories'] as List).cast<Map>())
                    MediaPipeCategory(
                      index: (value['index'] as num?)?.toInt() ?? -1,
                      score: (value['score'] as num).toDouble(),
                      categoryName: _label(value['categoryName']),
                      displayName: _label(value['displayName']),
                    ),
                ],
                headIndex: (head['headIndex'] as num?)?.toInt() ?? 0,
                headName: _label(head['headName']),
              ),
          ],
        ),
    ];

/// Google's browser and Android SDKs report an absent label as an empty
/// string; its C, Python and iOS APIs report none, as the Dart API does.
String? _label(Object? value) =>
    value is String && value.isNotEmpty ? value : null;
