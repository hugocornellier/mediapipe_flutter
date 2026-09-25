import 'dart:io';

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
