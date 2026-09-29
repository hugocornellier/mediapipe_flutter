/// Browser runtime location for the vision tasks.
abstract final class VisionWebRuntime {
  /// Optional directory containing the verified vision bundle and `wasm/`.
  /// Set before creating the first task. Relative URLs resolve against the app.
  /// When null, the pinned runtime loads from jsDelivr.
  static String? baseUrl;
}
