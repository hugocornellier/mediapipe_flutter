/// One decoder from the platform SDK adapters' results to the Dart types.
///
/// Google's browser runtime and its Android SDK both deliver Audio Classifier
/// results as JSON in the shape of Google's JavaScript API: one
/// classification result per chunk. The adapters only forward them.
library;

import 'package:mediapipe_core/platform_interface.dart'
    show decodeClassifications;

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
              decodeClassifications(head),
          ],
        ),
    ];
