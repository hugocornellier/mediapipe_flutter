import 'dart:ffi';

import 'third_party/mediapipe/generated/mediapipe_flutter_text_bindings.dart'
    as mp;

/// Fail before spawning an inherited legacy worker when its runtime is omitted.
void requireLegacyTextRuntime() {
  try {
    Native.addressOf<
      NativeFunction<
        Pointer<Void> Function(
          Pointer<mp.TextClassifierOptions>,
          Pointer<Pointer<Char>>,
        )
      >
    >(mp.text_classifier_create);
  } catch (_) {
    throw UnsupportedError(
      'The legacy TextClassifier, LanguageDetector and '
      'TextEmbedder APIs require the 2024 text runtime. They cannot be used '
      'with core.tasks_runtime: true. Use EmbeddingGemma for modern embeddings.',
    );
  }
}
