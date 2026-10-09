@TestOn('vm')
library;

import 'package:mediapipe_core/native_assets.dart';
import 'package:mediapipe_decision/mediapipe_decision.dart';
import 'package:mediapipe_decision/src/capabilities.dart'
    show decisionRuntimeTargets;
import 'package:test/test.dart';

// The capability tables answer for the library the hook bundles: the
// per-family decision library (familyRuntimes) and, where Google has none,
// the wheel's (wheelRuntimes), the one runtime that accepts the text-only
// EmbeddingGemma 2 model (UP-053).
void main() {
  test('the runtime targets are the hook\'s library targets', () {
    final family = familyRuntimes['decision']!.keys.toSet();
    final wheel = wheelRuntimes['decision']!.keys.toSet();
    // The simulator and 32-bit arm libraries serve the ios/arm64 and
    // android/arm64 process targets' builds.
    expect(
      decisionRuntimeTargets.keys.toSet(),
      {...family, ...wheel}.difference({'ios-simulator/arm64', 'android/arm'}),
    );
    expect(family.intersection(wheel), isEmpty);
  });

  test('the text-only EmbeddingGemma 2 targets are the wheel\'s', () {
    expect(
      embeddingGemma2TextTargets.keys.toSet(),
      wheelRuntimes['decision']!.keys.toSet(),
    );
  });
}
