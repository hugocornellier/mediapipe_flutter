import 'package:mediapipe_decision/mediapipe_decision.dart';
import 'package:mediapipe_decision/platform_interface.dart';
import 'package:mediapipe_decision/src/results/decoders.dart';
import 'package:test/test.dart';

TaskPlatform _platform(String os, String arch, [String? version]) =>
    TaskPlatform(operatingSystem: os, architecture: arch, version: version);

void main() {
  group('questions are checked the same way everywhere', () {
    test(
      'a boolean needs a threshold in [0, 1] and a positive temperature',
      () {
        expect(() => BooleanQuestion('x', threshold: 1.5), throwsArgumentError);
        expect(() => BooleanQuestion('x', temperature: 0), throwsArgumentError);
        expect(() => BooleanQuestion(''), throwsArgumentError);
        expect(() => BooleanQuestion('a\u0000b'), throwsArgumentError);
        expect(BooleanQuestion('x').toJson(), {
          'condition': 'x',
          'threshold': 0.5,
          'temperature': null,
          'normalizePrior': false,
        });
      },
    );

    test('a choice needs two options and a rubric two levels', () {
      expect(() => ChoiceQuestion({'only': 'one'}), throwsArgumentError);
      expect(() => ChoiceQuestion({'': 'a', 'b': 'b'}), throwsArgumentError);
      expect(() => ScoreQuestion(['low']), throwsArgumentError);
      expect(
        ChoiceQuestion({
          'a': 'A',
          'b': '',
        }, scoringMode: ChoiceScoringMode.fullOption).toJson()['scoringMode'],
        2,
      );
    });

    test('options refuse a non-positive token limit', () {
      expect(
        () => DecisionMakerOptions(modelPath: 'm.task', maxNumTokens: 0),
        throwsArgumentError,
      );
    });
  });

  group('results decode the same way from either runtime', () {
    final question = ChoiceQuestion({
      'shipping': 'Delivery',
      'billing': 'Charges',
      'other': 'Anything else',
    });

    test('choice probabilities follow the question, not the runtime', () {
      final result = decodeChoiceResult({
        'selectedKey': 'shipping',
        'probabilities': {'other': 0.01, 'shipping': 0.98, 'billing': 0.01},
        'confidence': 0.92,
      }, question);
      expect(result.probabilities.keys, ['shipping', 'billing', 'other']);
      expect(result.predictionSet, ['shipping']);
    });

    test('the prediction set covers 90% of the probability', () {
      final result = decodeChoiceResult({
        'selectedKey': 'billing',
        'probabilities': {'shipping': 0.3, 'billing': 0.65, 'other': 0.05},
        'confidence': 0.2,
      }, question);
      expect(result.predictionSet, ['billing', 'shipping']);
    });

    test('scores and booleans keep Google\'s numbers', () {
      final score = decodeScoreResult({
        'expectedScore': 1.25,
        'probabilities': [0.5, 0.25, 0.25],
        'confidence': 0.1,
        'selectedKey': '0',
      });
      expect(score.probabilities, [0.5, 0.25, 0.25]);
      expect(score.selectedKey, '0');
      final boolean = decodeBooleanResult({
        'value': true,
        'probabilityTrue': 1,
        'confidence': 1,
      });
      expect(boolean.probabilityTrue, 1.0);
    });
  });

  group('capabilities', () {
    test('the CPU on the three desktops, nothing on the phones', () {
      for (final (os, arch, version) in [
        ('macos', 'arm64', '15.0'),
        ('linux', 'x64', null),
        ('windows', 'x64', null),
      ]) {
        final capabilities = decisionMakerCapabilitiesForPlatform(
          _platform(os, arch, version),
        );
        expect(capabilities.supportedDelegates, {Delegate.cpu}, reason: os);
        expect(capabilities.runtimeVersion, '1.1.0');
      }
      for (final (os, arch) in [('android', 'arm64'), ('ios', 'arm64')]) {
        final capabilities = decisionMakerCapabilitiesForPlatform(
          _platform(os, arch, '17.0'),
        );
        expect(capabilities.isSupported, isFalse, reason: os);
        expect(
          capabilities.unavailableReasons[Delegate.cpu],
          contains('no C library'),
        );
      }
      expect(
        decisionMakerCapabilitiesForPlatform(
          _platform('macos', 'arm64', '13.0'),
        ).isSupported,
        isFalse,
      );
    });

    test('browsers get the GPU on a hardware WebGPU adapter (UP-049)', () {
      TaskPlatform web(String? gpu) => TaskPlatform(
        operatingSystem: 'web',
        architecture: 'unknown',
        gpu: gpu,
      );
      const metal = 'WebGPU apple metal-3';
      expect(
        decisionMakerCapabilitiesForPlatform(web(metal)).isSupported,
        isFalse,
        reason: 'no plugin',
      );
      decisionBackendFactory = (_) => throw UnimplementedError();
      addTearDown(() => decisionBackendFactory = null);
      final capabilities = decisionMakerCapabilitiesForPlatform(web(metal));
      expect(capabilities.supportedDelegates, {Delegate.gpu});
      expect(capabilities.unavailableReasons[Delegate.cpu], contains('UP-049'));
      for (final gpu in [
        null,
        'WebGPU google swiftshader',
        'WebGPU apple metal-3 (fallback adapter)',
        'Mali-G715 (ARM)',
      ]) {
        final refused = decisionMakerCapabilitiesForPlatform(web(gpu));
        expect(refused.isSupported, isFalse, reason: '$gpu');
        expect(refused.unavailableReasons[Delegate.gpu], contains('UP-049'));
      }
    });
  });
}
