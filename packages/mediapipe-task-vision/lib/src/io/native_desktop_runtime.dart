import 'dart:ffi';
import 'dart:io';

import 'package:mediapipe_flutter_core/io.dart'
    show missingLinuxGraphicsLibraries;

@Native<Void Function(Pointer<Char>)>(
  symbol: 'MpErrorFree',
  assetId: 'package:mediapipe_flutter_vision/vision.dylib',
)
external void _errorFree(Pointer<Char> error);

@Native<Void Function(Pointer<Char>)>(
  symbol: 'MpErrorFree',
  assetId: 'package:mediapipe_flutter_core/tasks_1_0_1.dylib',
)
external void _sharedErrorFree(Pointer<Char> error);

/// Loads the bundled official desktop monolith before resolving face aliases.
/// The OS loader reuses that image for its filename rather than loading a
/// second copy with another MediaPipe graph registry.
///
/// When the app also enables core's shared runtime for text and audio, core
/// bundles the library and every vision asset is such an alias, so core's copy
/// is loaded first.
void loadOfficialDesktopRuntime() {
  if (Platform.isLinux || Platform.isWindows) {
    try {
      Native.addressOf<NativeFunction<Void Function(Pointer<Char>)>>(
        _sharedErrorFree,
      );
    } on ArgumentError catch (error) {
      // Core bundles no runtime, and the vision asset is the bundled copy,
      // unless core's copy exists and cannot load.
      if (missingLinuxGraphicsLibraries('$error') case final missing?) {
        throw missing;
      }
    }
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
