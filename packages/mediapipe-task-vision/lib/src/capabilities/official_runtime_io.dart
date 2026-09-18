import 'dart:ffi';
import 'dart:io';

const _visionAsset = 'package:mediapipe_flutter_vision/vision.dylib';

// Google's wheel exports the public TensorFlow Lite version function. The
// source monolith deliberately exports only Mp* C APIs, so this harmless query
// distinguishes the exact runtime selected for the shared vision asset.
@Native<Pointer<Char> Function()>(
  symbol: 'TfLiteVersion',
  assetId: _visionAsset,
)
external Pointer<Char> _tfLiteVersion();

/// Whether the build hook mapped the shared vision asset to Google's monolith.
bool hasOfficialMacosLandmarkRuntime() {
  if (!Platform.isMacOS) return false;
  try {
    return _tfLiteVersion() != nullptr;
  } on ArgumentError {
    return false;
  }
}
