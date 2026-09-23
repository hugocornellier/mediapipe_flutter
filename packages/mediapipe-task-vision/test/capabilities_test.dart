import 'package:mediapipe_flutter_vision/capabilities.dart';
import 'package:test/test.dart';

void main() {
  test('image tasks expose desktop x64 CPU and fail closed elsewhere', () {
    for (final os in ['linux', 'windows']) {
      expect(
        imageTaskCapabilitiesForPlatform(
          TaskPlatform(operatingSystem: os, architecture: 'x64'),
        ).supportedDelegates,
        {VisionDelegate.cpu},
      );
    }
    expect(
      imageTaskCapabilitiesForPlatform(
        const TaskPlatform(
          operatingSystem: 'macos',
          architecture: 'arm64',
          version: '14.0',
        ),
      ).isSupported,
      isFalse,
    );
  });

  test('landmark tasks expose desktop x64 CPU and fail closed elsewhere', () {
    for (final os in ['linux', 'windows']) {
      expect(
        landmarkTaskCapabilitiesForPlatform(
          TaskPlatform(operatingSystem: os, architecture: 'x64'),
        ).supportedDelegates,
        {VisionDelegate.cpu},
      );
    }
    final mac = landmarkTaskCapabilitiesForPlatform(
      const TaskPlatform(
        operatingSystem: 'macos',
        architecture: 'arm64',
        version: '14.0',
      ),
    );
    expect(mac.isSupported, isFalse);
    expect(mac.unavailableReasons[VisionDelegate.cpu], contains('UP-004'));
    expect(mac.runtimeVersion, '1.0.0');
  });

  test('official and source macOS landmark capability claims stay split', () {
    const platform = TaskPlatform(
      operatingSystem: 'macos',
      architecture: 'arm64',
      version: '14.0',
    );
    expect(
      landmarkTaskCapabilitiesForPlatform(platform).supportedDelegates,
      isEmpty,
    );
    expect(
      landmarkTaskCapabilitiesForPlatform(
        platform,
        officialMacosRuntime: true,
      ).supportedDelegates,
      {VisionDelegate.cpu},
    );
  });
  test('Hand Landmarker follows each official runtime and adapter', () {
    TaskPlatform platform(String os, String architecture, [String? version]) =>
        TaskPlatform(
          operatingSystem: os,
          architecture: architecture,
          version: version,
        );
    const both = {VisionDelegate.cpu, VisionDelegate.gpu};
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
      {VisionDelegate.cpu},
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
      platform('web', 'unknown'),
    ]) {
      final capabilities = handLandmarkerCapabilitiesForPlatform(target);
      expect(capabilities.isSupported, isFalse);
      expect(
        capabilities.unavailableReasons[VisionDelegate.cpu],
        contains('adapter'),
      );
    }
  });

  test('MagicTouch reports its own GPU shader blocker', () {
    final result = interactiveSegmenterCapabilitiesForPlatform(
      const TaskPlatform(
        operatingSystem: 'macos',
        architecture: 'arm64',
        version: '14.0',
      ),
    );
    expect(result.supportedDelegates, {VisionDelegate.cpu});
    expect(result.unavailableReasons[VisionDelegate.gpu], contains('GLSL 330'));
  });

  test('Object Detector reports Metal only, with the CPU gap explained', () {
    final result = objectDetectorCapabilitiesForPlatform(
      const TaskPlatform(
        operatingSystem: 'macos',
        architecture: 'arm64',
        version: '14.0',
      ),
    );
    expect(result.supportedDelegates, {VisionDelegate.gpu});
    expect(result.isSupported, isTrue);
    expect(result.unavailableReasons[VisionDelegate.cpu], contains('UP-004'));
    expect(result.runtimeVersion, '1.0.0');
  });

  test('Face Landmarker offers GPU on Linux x64, not Windows', () {
    TaskCapabilities<VisionDelegate> on(String os) =>
        faceLandmarkerCapabilitiesForPlatform(
          TaskPlatform(operatingSystem: os, architecture: 'x64'),
        );
    expect(on('linux').supportedDelegates, {
      VisionDelegate.cpu,
      VisionDelegate.gpu,
    });
    expect(on('windows').supportedDelegates, {VisionDelegate.cpu});
    expect(on('windows').unavailableReasons[VisionDelegate.gpu], isNotNull);
  });

  test('Linux reports its official 1.0.1 runtime, Windows 1.0.0', () {
    for (final (os, version) in [('linux', '1.0.1'), ('windows', '1.0.0')]) {
      final platform = TaskPlatform(operatingSystem: os, architecture: 'x64');
      for (final result in [
        faceLandmarkerCapabilitiesForPlatform(platform),
        landmarkTaskCapabilitiesForPlatform(platform),
        segmenterTaskCapabilitiesForPlatform(platform),
        imageTaskCapabilitiesForPlatform(platform),
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
    expect(result.unavailableReasons[VisionDelegate.cpu], isNotNull);
    expect(result.unavailableReasons[VisionDelegate.gpu], isNotNull);
  });

  test('Object Detector desktop x64 supports CPU and explains GPU scope', () {
    for (final os in ['linux', 'windows']) {
      final result = objectDetectorCapabilitiesForPlatform(
        TaskPlatform(operatingSystem: os, architecture: 'x64'),
      );
      expect(result.supportedDelegates, {VisionDelegate.cpu});
      expect(result.unavailableReasons[VisionDelegate.gpu], contains('macOS'));
      expect(
        result.supportedTargets.keys,
        containsAll(['linux/x64', 'windows/x64', 'macos/arm64']),
      );
    }
  });
}
