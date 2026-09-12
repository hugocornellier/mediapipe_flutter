import 'package:mediapipe_flutter_core/native_assets.dart';

// A rebuild gets a new release tag and new digests. Never replace this asset
// in-place or resolve a floating "latest" URL from the build hook.
const DownloadAsset faceDetectorArchive = (
  url:
      'https://github.com/hugocornellier/mediapipe_flutter_native/releases/'
      'download/face-detector-v1.0.0-1/'
      'mediapipe-face-detector-1.0.0-macos-arm64.tar.gz',
  sha256: '5322692b9fa3ae1a59968f411a1964045ea1d733733a6654c82f046a45222c35',
);

const faceDetectorLibrarySha256 =
    '03d24557d891d932d08519f37e79917c7b991bb3d035a8d80efb294ab663e24f';

const DownloadAsset faceLandmarkerArchive = (
  url:
      'https://github.com/hugocornellier/mediapipe_flutter_native/releases/'
      'download/face-landmarker-v1.0.0-1/'
      'mediapipe-face-landmarker-1.0.0-macos-arm64.tar.gz',
  sha256: '25be1a3d71014fbe8e5b1423d4d2c8fbad9ff7c87998d976f2e081f43a9151ff',
);

const faceLandmarkerLibrarySha256 =
    '3481e64f0a3a4923cecd3db500444774f420d78f38226b91a838e3b330f80ea6';
