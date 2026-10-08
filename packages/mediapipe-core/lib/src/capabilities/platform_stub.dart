import 'task_capabilities.dart';

Future<TaskPlatform>? _platform;

/// Web has no packaged native task runtime. The GPU is what a registered
/// plugin's [taskPlatformGpuReader] names, such as the browser's WebGPU
/// adapter, read once.
Future<TaskPlatform> currentTaskPlatform() => _platform ??= _readPlatform();

Future<TaskPlatform> _readPlatform() async {
  String? gpu;
  if (taskPlatformGpuReader case final read?) {
    try {
      gpu = await read();
    } on Object {
      // An unnamed GPU leaves every capability table as declared.
    }
  }
  return TaskPlatform(
    operatingSystem: 'web',
    architecture: 'unknown',
    gpu: gpu,
  );
}

/// A browser is never Apple's iOS Simulator.
bool get runningInIosSimulator => false;
