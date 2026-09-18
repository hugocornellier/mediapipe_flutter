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
