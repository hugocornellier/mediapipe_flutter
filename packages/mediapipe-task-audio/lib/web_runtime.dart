/// Browser runtime location for the audio tasks.
abstract final class AudioWebRuntime {
  /// Optional directory containing the verified audio bundle and `wasm/`.
  /// Set before creating the first task. Relative URLs resolve against the app.
  /// When null, the pinned runtime loads from jsDelivr.
  static String? baseUrl;
}
