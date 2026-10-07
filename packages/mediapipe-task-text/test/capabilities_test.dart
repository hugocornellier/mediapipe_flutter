import 'package:mediapipe_text/mediapipe_text.dart';
import 'package:mediapipe_text/platform_interface.dart';
import 'package:test/test.dart';

/// Where core's runtime serves the text tasks (every task on CPU), and where
/// the registered Android and browser backends do.
const _runtime = [
  TaskPlatform(
    operatingSystem: 'macos',
    architecture: 'arm64',
    version: '26.4',
  ),
  TaskPlatform(operatingSystem: 'linux', architecture: 'x64'),
  TaskPlatform(operatingSystem: 'windows', architecture: 'x64'),
  TaskPlatform(operatingSystem: 'ios', architecture: 'arm64', version: '18.0'),
];
const _android = [
  TaskPlatform(operatingSystem: 'android', architecture: 'arm64'),
  TaskPlatform(operatingSystem: 'android', architecture: 'x64'),
];
const _web = TaskPlatform(operatingSystem: 'web', architecture: 'unknown');

Never _unused(String task, Map<String, Object?> options) =>
    throw UnimplementedError();

void main() {
  final every = <String, TaskCapabilities Function(TaskPlatform)>{
    'text classifier': textClassifierCapabilitiesForPlatform,
    'language detector': languageDetectorCapabilitiesForPlatform,
    'text embedder': textEmbedderCapabilitiesForPlatform,
    'EmbeddingGemma': (p) => textEmbedderCapabilitiesForPlatform(
      p,
      model: TextModels.embeddingGemma,
    ),
    'proofreader': textProofreaderCapabilitiesForPlatform,
    'summarizer': textSummarizerCapabilitiesForPlatform,
  };

  tearDown(() => textTaskBackendFactory = null);

  test("every task runs on the CPU of core's runtime targets", () {
    for (final platform in _runtime) {
      for (final MapEntry(key: name, value: claim) in every.entries) {
        final result = claim(platform);
        expect(result.supportedDelegates, {Delegate.cpu}, reason: name);
        expect(
          result.runtimeVersion,
          '1.1.0',
          reason: '$name on ${platform.target}',
        );
        expect(
          result.unavailableReasons[Delegate.gpu],
          contains('CPU'),
          reason: name,
        );
      }
    }
    final mac = textProofreaderCapabilitiesForPlatform(_runtime.first);
    expect(mac.minimumOperatingSystemVersion, '14.0');
    expect(
      textEmbedderCapabilitiesForPlatform(
        _runtime.first,
        model: TextModels.embeddingGemma,
      ).unavailableReasons[Delegate.gpu],
      contains('Metal'),
    );
  });

  test('nothing runs in browsers without the plugin', () {
    for (final MapEntry(key: name, value: claim) in every.entries) {
      expect(claim(_web).isSupported, isFalse, reason: name);
    }
  });

  test(
    "Google's text library serves every task on Android, with no plugin",
    () {
      for (final platform in _android) {
        for (final MapEntry(key: name, value: claim) in every.entries) {
          final result = claim(platform);
          expect(result.supportedDelegates, {Delegate.cpu}, reason: name);
          expect(result.runtimeVersion, '1.1.0');
        }
      }
    },
  );

  test('browsers run the classic tasks and EmbeddingGemma, not the '
      'generative tasks (UP-034)', () {
    textTaskBackendFactory = _unused;
    for (final name in [
      'text classifier',
      'language detector',
      'text embedder',
      'EmbeddingGemma',
    ]) {
      final result = every[name]!(_web);
      expect(result.supportedDelegates, {Delegate.cpu}, reason: name);
      expect(result.runtimeVersion, '1.0.1');
    }
    for (final name in ['proofreader', 'summarizer']) {
      final result = every[name]!(_web);
      expect(result.isSupported, isFalse, reason: name);
      for (final delegate in Delegate.values) {
        expect(
          result.unavailableReasons[delegate],
          contains('UP-034'),
          reason: '$name ${delegate.name}',
        );
      }
    }
  });

  test('a target outside every runtime is refused with the target list', () {
    textTaskBackendFactory = _unused;
    const other = TaskPlatform(operatingSystem: 'linux', architecture: 'arm64');
    for (final MapEntry(key: name, value: claim) in every.entries) {
      final result = claim(other);
      expect(result.isSupported, isFalse, reason: name);
      expect(result.unavailableReasons[Delegate.cpu], contains('linux/x64'));
    }
  });

  test('current-platform queries return a platform snapshot', () async {
    for (final result in [
      await queryTextEmbedderCapabilities(TextModels.embeddingGemma),
      await queryTextClassifierCapabilities(),
      await queryLanguageDetectorCapabilities(),
      await queryTextProofreaderCapabilities(),
      await queryTextSummarizerCapabilities(),
    ]) {
      expect(result.platform.operatingSystem, isNotEmpty);
      expect(result.supportedDelegates, isNot(contains(Delegate.gpu)));
    }
  });
}
