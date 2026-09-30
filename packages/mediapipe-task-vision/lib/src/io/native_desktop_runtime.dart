import 'dart:ffi';
import 'dart:io';

import 'package:mediapipe_core/io.dart' show missingLinuxGraphicsLibraries;

@Native<Void Function(Pointer<Char>)>(
  symbol: 'MpErrorFree',
  assetId: 'package:mediapipe_core/mediapipe.dylib',
)
external void _errorFree(Pointer<Char> error);

/// Loads core's copy of Google's desktop library before the face aliases
/// resolve. The face assets name that library's file, and the OS loader
/// reuses the image already loaded under that name rather than loading a
/// second copy with another MediaPipe graph registry.
void loadOfficialDesktopRuntime() {
  if (Platform.isLinux || Platform.isWindows) {
    final Pointer<NativeFunction<Void Function(Pointer<Char>)>> errorFree;
    try {
      errorFree = Native.addressOf(_errorFree);
    } on Object catch (error) {
      throw missingLinuxGraphicsLibraries('$error') ?? error;
    }
    if (errorFree == nullptr) {
      throw StateError(
        'The official desktop runtime has no error-free export.',
      );
    }
  }
}
