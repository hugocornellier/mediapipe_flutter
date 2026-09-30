import 'dart:ffi';
import 'dart:io';

/// Google's MediaPipe engine, which mediapipe_core bundles.
const _engineAsset = 'package:mediapipe_core/mediapipe.dylib';

// Google's library exports the public TensorFlow Lite version function, so
// this harmless query confirms the engine is bundled and loads.
@Native<Pointer<Char> Function()>(
  symbol: 'TfLiteVersion',
  assetId: _engineAsset,
)
external Pointer<Char> _tfLiteVersion();

/// Whether core bundled Google's macOS engine (`tasks_runtime: true`), which
/// every vision task except the source-built face pair runs on.
bool hasOfficialMacosLandmarkRuntime() {
  if (!Platform.isMacOS) return false;
  try {
    return _tfLiteVersion() != nullptr;
  } on ArgumentError {
    return false;
  }
}

@Native<Int Function()>(symbol: 'MpIosSdkVersion', assetId: _engineAsset)
external int _iosSdkVersion();

/// Whether core bundled its adapter over Google's official iOS SDK, the
/// default unless the app sets `official_ios_sdk: false`.
bool hasOfficialIosVisionRuntime() {
  if (!Platform.isIOS) return false;
  try {
    return _iosSdkVersion() == 10001;
  } on ArgumentError {
    return false;
  }
}

@Native<Void Function()>(
  symbol: 'MpFaceDetectorClose',
  assetId: 'package:mediapipe_vision/face_detector.dylib',
)
external void _faceDetectorClose();

/// Whether the app bundled the source-built Android face runtime
/// (`official_android_sdk: false`). With Google's SDK, the default, the face
/// assets are process lookups that resolve to nothing.
bool hasSourceBuiltAndroidFaceRuntime() {
  if (!Platform.isAndroid) return false;
  try {
    Native.addressOf<NativeFunction<Void Function()>>(_faceDetectorClose);
    return true;
  } on ArgumentError {
    return false;
  }
}
