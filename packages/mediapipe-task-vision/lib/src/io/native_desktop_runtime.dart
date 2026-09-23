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

/// Google's Linux runtime links EGL and OpenGL ES even for CPU inference, so a
/// system without them cannot load it at all. Names the packages to install.
StateError? missingLinuxGraphicsLibraries(String loaderError) {
  if (!Platform.isLinux ||
      !(loaderError.contains('libEGL') || loaderError.contains('libGLES'))) {
    return null;
  }
  return StateError(
    'Google\'s official MediaPipe Linux runtime needs the system EGL and '
    'OpenGL ES libraries (libEGL.so.1, libGLESv2.so.2), even for CPU '
    'inference. Install them, for example with '
    '`sudo apt-get install libegl1 libgles2` on Debian or Ubuntu. '
    'Loader error: $loaderError',
  );
}
