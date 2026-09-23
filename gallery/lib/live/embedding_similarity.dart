import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

/// An Image Embedder frame, with its cosine similarity to the first frame
/// after the demo started.
final class EmbeddingSimilarity {
  const EmbeddingSimilarity(this.result, this.similarity);
  final ImageEmbedderResult result;
  final double similarity;
}
