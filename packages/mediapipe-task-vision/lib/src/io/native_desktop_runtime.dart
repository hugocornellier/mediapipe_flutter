import 'dart:ffi';
import 'dart:io';

@Native<Void Function(Pointer<Char>)>(
  symbol: 'MpErrorFree',
  assetId: 'package:mediapipe_flutter_vision/vision.dylib',
)
external void _errorFree(Pointer<Char> error);

/// Loads the bundled official desktop monolith before resolving face aliases.
/// The OS loader reuses that image for its filename rather than loading a
/// second copy with another MediaPipe graph registry.
void loadOfficialDesktopRuntime() {
  if (Platform.isLinux || Platform.isWindows) {
    if (Native.addressOf<NativeFunction<Void Function(Pointer<Char>)>>(
          _errorFree,
        ) ==
        nullptr) {
      throw StateError(
        'The official desktop runtime has no error-free export.',
      );
    }
  }
}
