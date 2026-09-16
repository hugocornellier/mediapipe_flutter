import 'package:mediapipe_flutter_vision/capabilities.dart';
import 'package:test/test.dart';

void main() {
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

  test('Object Detector reports Metal only, with the CPU abort explained', () {
    final result = objectDetectorCapabilitiesForPlatform(
      const TaskPlatform(
        operatingSystem: 'macos',
        architecture: 'arm64',
        version: '14.0',
      ),
    );
    expect(result.supportedDelegates, {VisionDelegate.gpu});
    expect(result.isSupported, isTrue);
    expect(result.unavailableReasons[VisionDelegate.cpu], contains('SIGILL'));
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
