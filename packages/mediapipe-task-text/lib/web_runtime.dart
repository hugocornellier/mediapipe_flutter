/// Browser runtime location for the text tasks.
abstract final class TextWebRuntime {
  /// Optional directory containing the verified text bundle and `wasm/`.
  /// Set before creating the first task. Relative URLs resolve against the app.
  /// When null, the pinned runtime loads from jsDelivr.
  static String? baseUrl;
}
