import 'package:mediapipe_flutter_core/native_assets.dart';

// A rebuild gets a new release tag and new digests. Never replace this asset
// in-place or resolve a floating "latest" URL from the build hook.
const DownloadAsset faceDetectorArchive = (
  url:
      'https://github.com/hugocornellier/mediapipe_flutter_native/releases/'
      'download/face-detector-v1.0.0-2/'
      'mediapipe-face-detector-1.0.0-macos-arm64.tar.gz',
  sha256: 'bbebd7ef2cfd95df89a757f6d8620c1fb5a12a2d55c2858082fecacf979ab87c',
);

const faceDetectorLibrarySha256 =
    'c57d0698684e0abcb6a2cfb5a7d38855a7044a43c9714add50f92f36525c9497';

const DownloadAsset faceLandmarkerArchive = (
  url:
      'https://github.com/hugocornellier/mediapipe_flutter_native/releases/'
      'download/face-landmarker-v1.0.0-2/'
      'mediapipe-face-landmarker-1.0.0-macos-arm64.tar.gz',
  sha256: '0c72b6af47508a50a67a137bc5313c990d91da8a819041431bf6408aa5656f83',
);

const faceLandmarkerLibrarySha256 =
    '825cdbb58d763d87a0e35b8c38406ac738841ac7bbe1af6888de5b7e1074f4f9';
