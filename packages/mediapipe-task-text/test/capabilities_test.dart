import 'package:mediapipe_flutter_text/capabilities.dart';
import 'package:test/test.dart';

void main() {
  test('all modern text tasks declare CPU with task-specific GPU blockers', () {
    const platform = TaskPlatform(
      operatingSystem: 'macos',
      architecture: 'arm64',
      version: '26.4',
    );
    for (final task in TextTask.values) {
      final result = textTaskCapabilitiesForPlatform(task, platform);
      expect(result.runtimeVersion, '1.0.1');
      expect(result.minimumOperatingSystemVersion, '14.0');
      expect(result.supportedDelegates, {TextDelegate.cpu});
      expect(
        result.unavailableReasons[TextDelegate.gpu],
        contains(task == TextTask.embeddingGemma ? 'Metal' : 'only the CPU'),
      );
    }
  });

  test('current-platform query returns a platform snapshot', () async {
    final result = await queryTextTaskCapabilities(TextTask.embeddingGemma);
    expect(result.platform.operatingSystem, isNotEmpty);
    expect(result.supportedDelegates, isNot(contains(TextDelegate.gpu)));
  });
}
