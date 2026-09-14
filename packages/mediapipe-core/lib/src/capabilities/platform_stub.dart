import 'task_capabilities.dart';

/// Web has no packaged native task runtime.
Future<TaskPlatform> currentTaskPlatform() async =>
    const TaskPlatform(operatingSystem: 'web', architecture: 'unknown');
