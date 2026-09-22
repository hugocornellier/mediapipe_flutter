import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_vision/src/native_assets/vision_library.dart';
import 'package:test/test.dart';

import 'synthetic_macho.dart';

// The unsigned-image digest must ignore exactly what codesign rewrites and
// nothing else; otherwise either a new Xcode breaks the pin again or a
// tampered header slips through.
void main() {
  test('ignores the signature blob and the sizes codesign rewrites', () {
    final base = syntheticSignedMachO();
    final baseline = unsignedMachOSha256(base);
    expect(
      unsignedMachOSha256(syntheticSignedMachO(signature: [9, 9, 9, 9, 9, 9])),
      baseline,
      reason: 'a different, longer blob is the same image',
    );
    expect(
      unsignedMachOSha256(syntheticSignedMachO(signature: [])),
      baseline,
      reason: 'an empty blob is the same image',
    );
    expect(
      sha256.convert(base).toString(),
      isNot(sha256.convert(syntheticSignedMachO(signature: [1])).toString()),
      reason: 'the whole-file digest does change, which is the problem',
    );
  });

  test('changes with code, data and rewritten install names', () {
    final baseline = unsignedMachOSha256(syntheticSignedMachO());
    expect(
      unsignedMachOSha256(syntheticSignedMachO(payload: [7, 7, 7, 7])),
      isNot(baseline),
    );
    expect(
      unsignedMachOSha256(
        syntheticSignedMachO(installName: '@rpath/libtampered.dylib'),
      ),
      isNot(baseline),
    );
  });

  test('rejects anything that is not a thin 64-bit Mach-O', () {
    expect(
      () => unsignedMachOSha256(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(() => unsignedMachOSha256(Uint8List(64)), throwsFormatException);
  });
}
