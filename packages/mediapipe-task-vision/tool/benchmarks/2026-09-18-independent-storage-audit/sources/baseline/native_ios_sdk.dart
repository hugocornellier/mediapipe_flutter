import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../interface/face_detector_types.dart';

const _landmarkerAsset =
    'package:mediapipe_flutter_vision/face_landmarker.dylib';
const _detectorAsset = 'package:mediapipe_flutter_vision/face_detector.dylib';

@Native<Int Function()>(symbol: 'MpIosSdkVersion', assetId: _landmarkerAsset)
external int _landmarkerSdkVersion();

@Native<Int Function()>(symbol: 'MpIosSdkVersion', assetId: _detectorAsset)
external int _detectorSdkVersion();

/// Source-built iOS artifacts have no adapter marker, and stay CPU only.
bool hasOfficialIosFaceRuntime({bool detector = false}) {
  if (!Platform.isIOS) return false;
  try {
    return (detector ? _detectorSdkVersion() : _landmarkerSdkVersion()) ==
        10001;
  } on ArgumentError {
    return false;
  }
}

typedef _CreateBgraNative =
    UnsignedInt Function(
      Int,
      Int,
      Int,
      Pointer<Uint8>,
      Size,
      Pointer<Pointer<Void>>,
      Pointer<Pointer<Char>>,
    );

@Native<_CreateBgraNative>(
  symbol: 'MpIosImageCreateFromBgraData',
  assetId: _landmarkerAsset,
)
external int _landmarkerBgra(
  int width,
  int height,
  int stride,
  Pointer<Uint8> pixels,
  int length,
  Pointer<Pointer<Void>> image,
  Pointer<Pointer<Char>> error,
);

@Native<_CreateBgraNative>(
  symbol: 'MpIosImageCreateFromBgraData',
  assetId: _detectorAsset,
)
external int _detectorBgra(
  int width,
  int height,
  int stride,
  Pointer<Uint8> pixels,
  int length,
  Pointer<Pointer<Void>> image,
  Pointer<Pointer<Char>> error,
);

/// Retains BGRA and its row stride; the SDK's pixel buffer needs no swizzle.
int createOfficialIosBgraImage(
  VisionImage input,
  Arena arena,
  Pointer<Pointer<Void>> image,
  Pointer<Pointer<Char>> error, {
  bool detector = false,
}) {
  final bytes = input.pixels!;
  final pixels = arena<Uint8>(bytes.length);
  pixels.asTypedList(bytes.length).setAll(0, bytes);
  return (detector ? _detectorBgra : _landmarkerBgra)(
    input.width!,
    input.height!,
    input.bytesPerRow!,
    pixels,
    bytes.length,
    image,
    error,
  );
}
