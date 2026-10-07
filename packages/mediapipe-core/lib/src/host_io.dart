/// What the family packages need from the host when they call Google's C API.
library;

import 'dart:io';

/// Google's `MpHostSystem` value for this process, the way its Python API
/// fills `BaseOptions.host_system` from `platform.system()`.
int get mpHostSystem => Platform.isLinux
    ? 1
    : Platform.isMacOS
    ? 2
    : Platform.isWindows
    ? 3
    : Platform.isIOS
    ? 4
    : Platform.isAndroid
    ? 5
    : 0;

/// [path] as Google's C API should receive it: absolute on Android, whose
/// MediaPipe resource resolver reads a relative path as an asset inside the
/// app's APK rather than as a file.
String nativeModelPath(String path) =>
    Platform.isAndroid ? File(path).absolute.path : path;

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
