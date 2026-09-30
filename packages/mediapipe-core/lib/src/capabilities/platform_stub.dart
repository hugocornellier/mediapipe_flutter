import 'task_capabilities.dart';

/// Web has no packaged native task runtime.
Future<TaskPlatform> currentTaskPlatform() async =>
    const TaskPlatform(operatingSystem: 'web', architecture: 'unknown');

/// A browser is never Apple's iOS Simulator.
bool get runningInIosSimulator => false;
