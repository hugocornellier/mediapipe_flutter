/// Package support information, available without loading models or native tasks.
library;

export 'src/capabilities/task_capabilities.dart';
export 'src/capabilities/platform_stub.dart'
    if (dart.library.io) 'src/capabilities/platform_io.dart';
