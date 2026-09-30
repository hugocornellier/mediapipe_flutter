@TestOn('browser')
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:mediapipe_core/model_store.dart';
import 'package:test/test.dart';

void main() {
  test('Cache Storage reuses verified model bytes', () async {
    final bytes = utf8.encode('verified web model');
    final digest = sha256.convert(bytes).toString();
    final store = ModelStore();
    await store.clear();
    final online = DownloadAsset(
      url: 'data:application/octet-stream;base64,${base64.encode(bytes)}',
      sha256: digest,
    );
    expect(await store.get(online), bytes);
    final offline = DownloadAsset(
      url: 'https://invalid.example/model',
      sha256: digest,
    );
    expect(await store.get(offline), bytes);
    await store.clear();
  });
}
