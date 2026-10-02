import 'package:mediapipe_vision/mediapipe_vision.dart';
import 'package:mediapipe_vision/platform_interface.dart';
import 'package:test/test.dart';

void main() {
  test('Hand Landmarker follows each official runtime and adapter', () {
    TaskPlatform platform(String os, String architecture, [String? version]) =>
        TaskPlatform(
          operatingSystem: os,
          architecture: architecture,
          version: version,
        );
    const both = {Delegate.cpu, Delegate.gpu};
    // Linux's 1.0.1 wheel has GPU built in; Windows' has it compiled out.
    expect(
      handLandmarkerCapabilitiesForPlatform(
        platform('linux', 'x64'),
      ).supportedDelegates,
      both,
    );
    expect(
      handLandmarkerCapabilitiesForPlatform(
        platform('windows', 'x64'),
      ).supportedDelegates,
      {Delegate.cpu},
    );
    // macOS and iOS only with the official runtime or SDK adapter.
    final mac = platform('macos', 'arm64', '14.0');
    expect(handLandmarkerCapabilitiesForPlatform(mac).isSupported, isFalse);
    expect(
      handLandmarkerCapabilitiesForPlatform(
        mac,
        officialMacosRuntime: true,
      ).supportedDelegates,
      both,
    );
    final ios = platform('ios', 'arm64', '15.0');
    expect(handLandmarkerCapabilitiesForPlatform(ios).isSupported, isFalse);
    final official = handLandmarkerCapabilitiesForPlatform(
      ios,
      officialIosRuntime: true,
    );
    expect(official.supportedDelegates, both);
    expect(official.runtimeVersion, '1.0.1');
    // Android and web need their registered SDK adapters, absent here.
    for (final target in [
      platform('android', 'arm64'),
      platform('android', 'x64'),
      platform('web', 'unknown'),
    ]) {
      final capabilities = handLandmarkerCapabilitiesForPlatform(target);
      expect(capabilities.isSupported, isFalse);
      expect(
        capabilities.unavailableReasons[Delegate.cpu],
        contains('adapter'),
      );
    }
  });

  test('MagicTouch reports its own GPU shader blocker', () {
    const mac = TaskPlatform(
      operatingSystem: 'macos',
      architecture: 'arm64',
      version: '14.0',
    );
    final result = interactiveSegmenterCapabilitiesForPlatform(
      mac,
      officialMacosRuntime: true,
    );
    expect(result.supportedDelegates, {Delegate.cpu});
    expect(result.unavailableReasons[Delegate.gpu], contains('GLSL 330'));
    expect(result.runtimeVersion, '1.0.0');
    // Without Google's engine the reason names the one setting.
    final off = interactiveSegmenterCapabilitiesForPlatform(mac);
    expect(off.isSupported, isFalse);
    expect(
      off.unavailableReasons[Delegate.cpu],
      contains('tasks_runtime: true'),
    );
  });

  test("Object Detector runs CPU and Metal on Google's macOS engine", () {
    const mac = TaskPlatform(
      operatingSystem: 'macos',
      architecture: 'arm64',
      version: '14.0',
    );
    final result = objectDetectorCapabilitiesForPlatform(
      mac,
      officialMacosRuntime: true,
    );
    expect(result.supportedDelegates, {Delegate.cpu, Delegate.gpu});
    expect(result.runtimeVersion, '1.0.0');
    final off = objectDetectorCapabilitiesForPlatform(mac);
    expect(off.isSupported, isFalse);
    for (final delegate in Delegate.values) {
      expect(
        off.unavailableReasons[delegate],
        contains('tasks_runtime: true'),
        reason: delegate.name,
      );
    }
  });

  test('Face Landmarker offers GPU on Linux x64, not Windows', () {
    TaskCapabilities on(String os) => faceLandmarkerCapabilitiesForPlatform(
      TaskPlatform(operatingSystem: os, architecture: 'x64'),
    );
    expect(on('linux').supportedDelegates, {Delegate.cpu, Delegate.gpu});
    expect(on('windows').supportedDelegates, {Delegate.cpu});
    expect(on('windows').unavailableReasons[Delegate.gpu], isNotNull);
  });

  test('Linux reports its official 1.0.1 runtime, Windows 1.0.0', () {
    for (final (os, version) in [('linux', '1.0.1'), ('windows', '1.0.0')]) {
      final platform = TaskPlatform(operatingSystem: os, architecture: 'x64');
      for (final result in [
        faceLandmarkerCapabilitiesForPlatform(platform),
        poseLandmarkerCapabilitiesForPlatform(platform),
        imageSegmenterCapabilitiesForPlatform(platform),
        imageClassifierCapabilitiesForPlatform(platform),
        objectDetectorCapabilitiesForPlatform(platform),
      ]) {
        expect(result.runtimeVersion, version);
      }
    }
  });

  test('an unsupported platform fails closed for both delegates', () {
    final result = objectDetectorCapabilitiesForPlatform(
      const TaskPlatform(
        operatingSystem: 'linux',
        architecture: 'arm64',
        version: '1.0',
      ),
    );
    expect(result.supportedDelegates, isEmpty);
    expect(result.isSupported, isFalse);
    // The platform itself is the blocker, so it explains both delegates.
    expect(result.unavailableReasons[Delegate.cpu], isNotNull);
    expect(result.unavailableReasons[Delegate.gpu], isNotNull);
  });

  test('Object Detector desktop x64: Linux GPU, Windows CPU only', () {
    final linux = objectDetectorCapabilitiesForPlatform(
      const TaskPlatform(operatingSystem: 'linux', architecture: 'x64'),
    );
    expect(linux.supportedDelegates, {Delegate.cpu, Delegate.gpu});
    final windows = objectDetectorCapabilitiesForPlatform(
      const TaskPlatform(operatingSystem: 'windows', architecture: 'x64'),
    );
    expect(windows.supportedDelegates, {Delegate.cpu});
    expect(windows.unavailableReasons[Delegate.gpu], contains('Linux'));
    expect(
      windows.supportedTargets.keys,
      containsAll(['linux/x64', 'windows/x64']),
    );
  });

  test('desktop GPU where Google\'s desktop runtimes run the task', () {
    const linux = TaskPlatform(operatingSystem: 'linux', architecture: 'x64');
    const windows = TaskPlatform(
      operatingSystem: 'windows',
      architecture: 'x64',
    );
    const macos = TaskPlatform(
      operatingSystem: 'macos',
      architecture: 'arm64',
      version: '15.0',
    );
    for (final (claim, onLinux, onMac) in [
      (poseLandmarkerCapabilitiesForPlatform, true, true),
      (gestureRecognizerCapabilitiesForPlatform, true, true),
      (imageClassifierCapabilitiesForPlatform, true, true),
      (imageSegmenterCapabilitiesForPlatform, true, true),
      // UP-027: Google's Linux runtime aborts the embedder on GPU.
      (imageEmbedderCapabilitiesForPlatform, false, true),
      // UP-026: neither runtime opens Holistic's blendshapes model on GPU.
      (holisticLandmarkerCapabilitiesForPlatform, false, false),
    ]) {
      expect(claim(linux).supportedDelegates.contains(Delegate.gpu), onLinux);
      expect(claim(windows).supportedDelegates, isNot(contains(Delegate.gpu)));
      // Metal through the official macOS runtime only.
      expect(claim(macos).supportedDelegates, isEmpty);
      expect(
        claim(
          macos,
          officialMacosRuntime: true,
        ).supportedDelegates.contains(Delegate.gpu),
        onMac,
      );
    }
    expect(
      holisticLandmarkerCapabilitiesForPlatform(
        linux,
      ).unavailableReasons[Delegate.gpu],
      contains('UP-026'),
    );
  });

  test(
    'Image Segmenter offers only CPU on an Android PowerVR GPU (UP-023)',
    () {
      // The Android adapter registers this; a stub stands in for it here.
      imageSegmenterBackendFactory = (_) => throw UnimplementedError();
      addTearDown(() => imageSegmenterBackendFactory = null);
      TaskPlatform android(String? gpu) => TaskPlatform(
        operatingSystem: 'android',
        architecture: 'arm64',
        gpu: gpu,
      );
      for (final gpu in [
        'PowerVR D-Series DXT-48-1536 (Imagination Technologies)',
        'PowerVR Rogue GE8320 (Imagination Technologies)',
      ]) {
        final capabilities = imageSegmenterCapabilitiesForPlatform(
          android(gpu),
        );
        expect(capabilities.supportedDelegates, {Delegate.cpu}, reason: gpu);
        expect(
          capabilities.unavailableReasons[Delegate.gpu],
          allOf(contains('UP-023'), contains(gpu)),
        );
      }
      // Other GPUs, and a GPU the adapter could not name, keep both delegates.
      for (final gpu in [
        'Mali-G715 (ARM)',
        'Adreno (TM) 750 (Qualcomm)',
        null,
      ]) {
        expect(
          imageSegmenterCapabilitiesForPlatform(
            android(gpu),
          ).supportedDelegates,
          {Delegate.cpu, Delegate.gpu},
          reason: gpu,
        );
      }
      // Only Image Segmenter is withdrawn, and only on Android.
      imageClassifierBackendFactory = (_) => throw UnimplementedError();
      addTearDown(() => imageClassifierBackendFactory = null);
      expect(
        imageClassifierCapabilitiesForPlatform(
          android('PowerVR Rogue GE8320 (Imagination Technologies)'),
        ).supportedDelegates,
        contains(Delegate.gpu),
      );
      const linuxPowerVr = TaskPlatform(
        operatingSystem: 'linux',
        architecture: 'x64',
        gpu: 'PowerVR B-Series BXE-4-32 (Imagination Technologies)',
      );
      expect(
        imageSegmenterCapabilitiesForPlatform(linuxPowerVr).supportedDelegates,
        contains(Delegate.gpu),
      );
    },
  );

  test('the iOS Simulator offers the CPU only (UP-031)', () {
    // Google's iOS SDK aborts the app on the simulator's Metal path, so every
    // task that runs GPU on an iPhone offers only the CPU there.
    const device = TaskPlatform(
      operatingSystem: 'ios',
      architecture: 'arm64',
      version: '26.4',
    );
    const simulator = TaskPlatform(
      operatingSystem: 'ios',
      architecture: 'arm64',
      version: '26.4',
      simulator: true,
    );
    final tables = <String, TaskCapabilities Function(TaskPlatform)>{
      'face landmarker': faceLandmarkerCapabilitiesForPlatform,
      'face detector': faceDetectorCapabilitiesForPlatform,
      'hand landmarker': (platform) => handLandmarkerCapabilitiesForPlatform(
        platform,
        officialIosRuntime: true,
      ),
      'pose landmarker': (platform) => poseLandmarkerCapabilitiesForPlatform(
        platform,
        officialIosRuntime: true,
      ),
      'image segmenter': (platform) => imageSegmenterCapabilitiesForPlatform(
        platform,
        officialIosRuntime: true,
      ),
      'object detector': (platform) => objectDetectorCapabilitiesForPlatform(
        platform,
        officialIosRuntime: true,
      ),
    };
    for (final MapEntry(key: task, value: table) in tables.entries) {
      expect(table(device).supportedDelegates, {
        Delegate.cpu,
        Delegate.gpu,
      }, reason: task);
      final capabilities = table(simulator);
      expect(capabilities.supportedDelegates, {Delegate.cpu}, reason: task);
      expect(
        capabilities.unavailableReasons[Delegate.gpu],
        contains('UP-031'),
        reason: task,
      );
    }
    // Without Google's SDK the simulator has no runtime, and says so rather
    // than blaming the GPU.
    expect(
      handLandmarkerCapabilitiesForPlatform(
        simulator,
      ).unavailableReasons[Delegate.gpu],
      isNot(contains('UP-031')),
    );
  });
}
