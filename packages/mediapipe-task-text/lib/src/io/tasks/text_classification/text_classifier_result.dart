import 'dart:ffi';
import 'package:mediapipe_flutter_core/io.dart';
import 'package:mediapipe_flutter_text/interface.dart';
import '../../classic_text_runtime.dart';
import '../../third_party/mediapipe/classic_text_bindings.dart' as mp;

/// Owned classification output. No native allocation is retained.
///
/// Calling dispose is optional and idempotent; values remain readable.
class TextClassifierResult extends BaseTextClassifierResult {
  /// Snapshot the ordered output heads and categories.
  TextClassifierResult({
    required Iterable<Classifications> classifications,
    this.timestampMs,
  }) : classifications = List.unmodifiable([
         for (final head in classifications)
           Classifications(
             categories: List<Category>.unmodifiable([
               for (final category in head.categories)
                 Category(
                   index: category.index,
                   score: category.score,
                   categoryName: category.categoryName,
                   displayName: category.displayName,
                 ),
             ]),
             headIndex: head.headIndex,
             headName: head.headName,
           ),
       ]);

  /// Copy a borrowed 1.0.1 result immediately; the caller retains ownership.
  factory TextClassifierResult.native(
    Pointer<mp.MpClassificationResult> pointer,
  ) {
    final result = pointer.ref;
    return TextClassifierResult(
      timestampMs: result.hasTimestampMs ? result.timestampMs : null,
      classifications: [
        for (var i = 0; i < result.classificationsCount; i++)
          _copyHead(result.classifications[i]),
      ],
    );
  }

  @override
  final List<Classifications> classifications;

  /// Optional timestamp supplied by MediaPipe.
  final int? timestampMs;
}

Classifications _copyHead(mp.MpClassifications head) => Classifications(
  categories: [
    for (var i = 0; i < head.categoriesCount; i++)
      Category(
        index: head.categories[i].index,
        score: head.categories[i].score,
        categoryName: textTaskString(head.categories[i].categoryName),
        displayName: textTaskString(head.categories[i].displayName),
      ),
  ],
  headIndex: head.headIndex,
  headName: textTaskString(head.headName),
);
