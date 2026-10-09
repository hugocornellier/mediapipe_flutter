/// Browsers have no native runtime: the retrieval tasks run through the
/// registered browser plugin, so reaching this means it did not register.
library;

import 'package:mediapipe_core/mediapipe_core.dart';

import '../retrieval_backend.dart';
import '../types/options.dart';

/// The native Universal Embedder; browsers have none.
Future<RetrievalBackend> openNativeUniversalEmbedder(
  UniversalEmbedderOptions options,
) async => throw const RuntimeUnavailableException(
  'The MediaPipe Retrieval browser plugin did not register.',
  fix:
      'Depend on mediapipe_retrieval as a Flutter plugin so its web '
      'registration runs before the first task is created.',
);
