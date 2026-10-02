import 'package:mediapipe_text/mediapipe_text.dart';
import 'package:test/test.dart';

void main() {
  const mac = TaskPlatform(
    operatingSystem: 'macos',
    architecture: 'arm64',
    version: '26.4',
  );

  test('the generative tasks declare macOS CPU with their GPU blockers', () {
    for (final (result, blocker) in [
      (
        textEmbedderCapabilitiesForPlatform(
          mac,
          model: TextModels.embeddingGemma,
        ),
        'Metal',
      ),
      (textProofreaderCapabilitiesForPlatform(mac), 'only the CPU'),
      (textSummarizerCapabilitiesForPlatform(mac), 'only the CPU'),
    ]) {
      expect(result.runtimeVersion, '1.0.1');
      expect(result.minimumOperatingSystemVersion, '14.0');
      expect(result.supportedDelegates, {Delegate.cpu});
      expect(result.unavailableReasons[Delegate.gpu], contains(blocker));
    }
  });

  test('EmbeddingGemma runs on macOS only; the classic embedders wider', () {
    const linux = TaskPlatform(operatingSystem: 'linux', architecture: 'x64');
    expect(
      textEmbedderCapabilitiesForPlatform(
        linux,
        model: TextModels.embeddingGemma,
      ).isSupported,
      isFalse,
    );
    for (final result in [
      textEmbedderCapabilitiesForPlatform(linux),
      textEmbedderCapabilitiesForPlatform(
        linux,
        model: TextModels.universalSentenceEncoder,
      ),
      textClassifierCapabilitiesForPlatform(linux),
      languageDetectorCapabilitiesForPlatform(linux),
    ]) {
      expect(result.supportedDelegates, {Delegate.cpu});
      expect(result.unavailableReasons[Delegate.gpu], contains('CPU only'));
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
