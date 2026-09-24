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
