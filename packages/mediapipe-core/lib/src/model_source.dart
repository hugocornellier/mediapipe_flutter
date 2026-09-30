import 'dart:typed_data';

/// A model source after a pinned download has been resolved.
final class ModelSource {
  /// Exactly one of [path] or [bytes] is available.
  const ModelSource({this.path, this.bytes});

  /// Native file path, when available.
  final String? path;

  /// Verified browser bytes, when available.
  final Uint8List? bytes;
}
