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
}
