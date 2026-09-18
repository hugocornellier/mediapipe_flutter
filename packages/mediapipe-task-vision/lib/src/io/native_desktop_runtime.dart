import 'dart:ffi';
import 'dart:io';

@Native<Pointer<Char> Function()>(
  symbol: 'TfLiteVersion',
  assetId: 'package:mediapipe_flutter_vision/vision.dylib',
)
external Pointer<Char> _tfLiteVersion();

/// Loads the bundled official desktop monolith before resolving face aliases.
/// The OS loader reuses that image for its filename rather than loading a
/// second copy with another MediaPipe graph registry.
void loadOfficialDesktopRuntime() {
  if (Platform.isLinux || Platform.isWindows) {
    if (_tfLiteVersion() == nullptr) {
      throw StateError('The official desktop runtime has no LiteRT version.');
    }
  }
}
