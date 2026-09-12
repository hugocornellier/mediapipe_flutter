import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:test/test.dart';

const _fixtures = 'test/fixtures/face_detection';

VisionImage fixtureImage(Map<String, dynamic> expected) {
  if (expected['file'] case final String name) {
    final file = File('$_fixtures/$name');
    expect(
      sha256.convert(file.readAsBytesSync()).toString(),
      expected['sha256'],
    );
    return VisionImage.fromFile(file.path);
  }
  var pixels = Uint8List(
    (expected['width'] as int) * (expected['height'] as int) * 3,
  );
  var format = VisionPixelFormat.rgb;
  if (expected['raw'] case final String name) {
    pixels = File('$_fixtures/$name').readAsBytesSync();
    expect(sha256.convert(pixels).toString(), expected['sha256']);
    if (expected['name'] == 'rgba') {
      final rgba = Uint8List(301 * 209 * 4);
      for (var i = 0; i < 301 * 209; i++) {
        rgba.setRange(i * 4, i * 4 + 3, pixels, i * 3);
        rgba[i * 4 + 3] = 255;
      }
      pixels = rgba;
      format = VisionPixelFormat.rgba;
    } else if (expected['name'] == 'rgb-rotated') {
      final rotated = Uint8List(pixels.length);
      for (var y = 0; y < 209; y++) {
        for (var x = 0; x < 301; x++) {
          final destination = ((301 - 1 - x) * 209 + y) * 3;
          rotated.setRange(
            destination,
            destination + 3,
            pixels,
            (y * 301 + x) * 3,
          );
        }
      }
      pixels = rotated;
    } else if (expected['name'] == 'rgb-pair') {
      final pair = Uint8List(360 * 209 * 3);
      for (var y = 0; y < 209; y++) {
        for (var face = 0; face < 2; face++) {
          final offset = (y * 360 + face * 180) * 3;
          pair.setRange(offset, offset + 180 * 3, pixels, (y * 301 + 60) * 3);
        }
      }
      pixels = pair;
    }
  }
  return VisionImage.fromPixels(
    pixels: pixels,
    width: expected['width'] as int,
    height: expected['height'] as int,
    format: format,
  );
}
