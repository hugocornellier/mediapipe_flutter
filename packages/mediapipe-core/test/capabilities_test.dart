import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart';
import 'package:test/test.dart';

TaskCapabilities _support(TaskPlatform platform) => TaskCapabilities.macosCpu(
  platform: platform,
  gpuUnavailableReason: 'Upstream GPU failure.',
);

void main() {
  test(
    'delegate-specific target and minimum versions are checked independently',
    () {
      TaskCapabilities check(String os, String? version) =>
          TaskCapabilities.onTargets(
            platform: TaskPlatform(
              operatingSystem: os,
              architecture: 'x64',
              version: version,
            ),
            delegates: const {
              Delegate.cpu: {'windows/x64': '10.0', 'linux/x64': null},
              Delegate.gpu: {'windows/x64': '11.0'},
            },
            unavailableReasons: const {Delegate.gpu: 'GPU requires Windows.'},
            runtimeVersion: '1.0.0',
          );
      expect(check('windows', '10.0').supportedDelegates, {Delegate.cpu});
      expect(
        check('windows', '10.0').unavailableReasons[Delegate.gpu],
        contains('11.0'),
      );
      expect(
        check('windows', '11.0').supportedDelegates,
        Delegate.values.toSet(),
      );
      expect(check('windows', null).supportedDelegates, isEmpty);
      expect(check('linux', null).supportedDelegates, {Delegate.cpu});
      expect(
        check('linux', null).unavailableReasons[Delegate.gpu],
        'GPU requires Windows.',
      );
      expect(check('windows', '11.0').minimumOperatingSystemVersion, '10.0');
      expect(
        () => check('linux', null).supportedTargets.clear(),
        throwsUnsupportedError,
      );
    },
  );
  test('minimum OS accepts CPU and preserves the upstream GPU explanation', () {
    final result = _support(
      const TaskPlatform(
        operatingSystem: 'macos',
        architecture: 'arm64',
        version: '14.0',
      ),
    );
    expect(result.supportedDelegates, {Delegate.cpu});
    expect(result.unavailableReasons[Delegate.gpu], 'Upstream GPU failure.');
    expect(result.unavailableReasons.containsKey(Delegate.cpu), isFalse);
    expect(
      () => result.supportedDelegates.add(Delegate.gpu),
      throwsUnsupportedError,
    );
    expect(() => result.unavailableReasons.clear(), throwsUnsupportedError);
  });

  test('old, unknown, Intel/Rosetta, mobile and web platforms fail closed', () {
    for (final platform in [
      const TaskPlatform(
        operatingSystem: 'macos',
        architecture: 'arm64',
        version: '13.6',
      ),
      const TaskPlatform(operatingSystem: 'macos', architecture: 'arm64'),
      const TaskPlatform(
        operatingSystem: 'macos',
        architecture: 'x64',
        version: '26.4',
      ),
      const TaskPlatform(
        operatingSystem: 'ios',
        architecture: 'arm64',
        version: '26.4',
      ),
      const TaskPlatform(operatingSystem: 'linux', architecture: 'arm64'),
      const TaskPlatform(operatingSystem: 'web', architecture: 'unknown'),
    ]) {
      final result = _support(platform);
      expect(result.isSupported, isFalse);
      expect(result.unavailableReasons.keys, containsAll(Delegate.values));
    }
  });

  test(
    'current platform inspection succeeds without MediaPipe native assets',
    () async {
      final platform = await currentTaskPlatform();
      expect(platform.operatingSystem, isNotEmpty);
      // Both Darwin systems answer kern.osproductversion, and a capability
      // table that carries a minimum version needs it on either one.
      if (platform.operatingSystem == 'macos' ||
          platform.operatingSystem == 'ios') {
        expect(platform.version, matches(r'^\d+(\.\d+)*$'));
        expect(platform.architecture, anyOf('arm64', 'x64'));
      }
    },
  );
}
