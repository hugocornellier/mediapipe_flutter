import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

/// Image Embedder output, optionally compared with the first camera frame.
final class EmbeddingSimilarity {
  const EmbeddingSimilarity(this.result, this.similarity);
  final ImageEmbedderResult result;
  final double? similarity;
}
