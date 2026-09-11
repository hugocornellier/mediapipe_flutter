// Pinned upstream 2024 runtimes. Update binaries and headers together.
// SHA-256 values verified from the original Google-hosted artifacts.
import 'package:mediapipe_flutter_core/native_assets.dart';

const sdkDownloads = <String, Map<String, DownloadAsset>>{
  'android': {
    'arm64': (
      url:
          'https://storage.googleapis.com/mediapipe-nightly-public/prod/mediapipe/gcp_ubuntu_flutter/release/40/20240419-150307/android_arm64/libtext.so',
      sha256:
          'f6a98ea58c2d65a8be2b14748f17df8dd014bc0253281a2e736ef8ab532c36d0',
    ),
  },
  'macos': {
    'arm64': (
      url:
          'https://storage.googleapis.com/mediapipe-nightly-public/prod/mediapipe/macos_flutter/release/61/20240508-094837/darwin_arm64/libtext.dylib',
      sha256:
          '3421348c0947d81ded0631703eaa1e8be6cb401809e334706d1d7f5bdca1ae96',
    ),
    'x64': (
      url:
          'https://storage.googleapis.com/mediapipe-nightly-public/prod/mediapipe/macos_flutter/release/61/20240508-094837/darwin_x86_64/libtext.dylib',
      sha256:
          '42544eb21eddb96be6efabd405f288c94a9b2499a78b5ea71cf76a7673eeb0aa',
    ),
  },
  'ios': {
    'arm64': (
      url:
          'https://storage.googleapis.com/mediapipe-nightly-public/prod/mediapipe/macos_flutter/release/61/20240508-094837/ios_arm64/libtext.dylib',
      sha256:
          '17dbe633a8570ccddea76d12793e69dca335f81eef7ec5fbe083d0ed88181813',
    ),
  },
};
