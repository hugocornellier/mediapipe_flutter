// Pinned upstream 2024 runtimes. Update binaries and headers together.
// SHA-256 values verified from the original Google-hosted artifacts.
import 'package:mediapipe_flutter_core/native_assets.dart';

const sdkDownloads = <String, Map<String, DownloadAsset>>{
  'android': {
    'arm64': (
      url:
          'https://storage.googleapis.com/mediapipe-nightly-public/prod/mediapipe/gcp_ubuntu_flutter/release/40/20240419-150307/android_arm64/libllm_inference_engine.so',
      sha256:
          '7120859b6e6ba3f0c0178f521e04474d2c1f45c3a671c8eb960be9ed40fb0818',
    ),
  },
  'macos': {
    'arm64': (
      url:
          'https://storage.googleapis.com/mediapipe-nightly-public/prod/mediapipe/macos_flutter/release/61/20240508-094837/darwin_arm64/libllm_inference_engine.dylib',
      sha256:
          'c702b63c52ae525b01be3f87fcb285cdf5953de8ee033e2d5a67684ab6aaf5c9',
    ),
  },
  'ios': {
    'arm64': (
      url:
          'https://storage.googleapis.com/mediapipe-nightly-public/prod/mediapipe/macos_flutter/release/61/20240508-094837/ios_arm64/libllm_inference_engine.dylib',
      sha256:
          '43463edd9ed451ea908c655b0c5bd30168d71a8e81c3ffbcd5d37ef59b7164c2',
    ),
  },
};
