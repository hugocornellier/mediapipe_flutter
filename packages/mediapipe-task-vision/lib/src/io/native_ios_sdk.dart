import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../interface/face_detector_types.dart';

const _landmarkerAsset =
    'package:mediapipe_flutter_vision/face_landmarker.dylib';
const _detectorAsset = 'package:mediapipe_flutter_vision/face_detector.dylib';

// Present for every task the adapter serves; the pool is task-independent.
const _visionAsset = 'package:mediapipe_flutter_vision/vision.dylib';

/// Benchmark overrides: 0 baseline, 1 reusable staging, 2 pool, 3 both.
/// Pixel pooling improved image creation and 1080p throughput in device A/B runs.
/// Staging reuse remains an explicit experimental override.
const iosImageStorageMode = int.fromEnvironment(
  'MEDIAPIPE_IOS_IMAGE_STORAGE',
  defaultValue: 2,
);

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
  assetId: _visionAsset,
)
external int _bgra(
  int width,
  int height,
  int stride,
  Pointer<Uint8> pixels,
  int length,
  Pointer<Pointer<Void>> image,
  Pointer<Pointer<Char>> error,
);

@Native<Pointer<Void> Function()>(
  symbol: 'MpIosPixelBufferPoolCreate',
  assetId: _visionAsset,
)
external Pointer<Void> _poolCreate();

@Native<Void Function(Pointer<Void>)>(
  symbol: 'MpIosPixelBufferPoolFree',
  assetId: _visionAsset,
)
external void _poolFree(Pointer<Void> pool);

@Native<
  UnsignedInt Function(
    Pointer<Void>,
    Int,
    Int,
    Int,
    Pointer<Uint8>,
    Size,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpIosImageCreateFromBgraDataWithPool', assetId: _visionAsset)
external int _pooledBgra(
  Pointer<Void> pool,
  int width,
  int height,
  int stride,
  Pointer<Uint8> pixels,
  int length,
  Pointer<Pointer<Void>> image,
  Pointer<Pointer<Char>> error,
);

/// Task-owned storage. Detection is serialized by the existing worker.
final class IosBgraStorage {
  /// Selects staging reuse (bit 0) and pixel-buffer pooling (bit 1).
  IosBgraStorage(this.mode);

  /// Independent candidates selected for this task's lifetime.
  final int mode;
  Pointer<Uint8> _pixels = nullptr;
  int _capacity = 0;
  Pointer<Void> _pool = nullptr;

  /// Copies one owned snapshot into an SDK-compatible image.
  int create(
    VisionImage input,
    Arena arena,
    Pointer<Pointer<Void>> image,
    Pointer<Pointer<Char>> error,
  ) {
    final bytes = input.pixels!;
    Pointer<Uint8> pixels;
    if (mode & 1 != 0) {
      if (bytes.length > _capacity) {
        final replacement = malloc<Uint8>(bytes.length);
        if (_pixels != nullptr) malloc.free(_pixels);
        _pixels = replacement;
        _capacity = bytes.length;
      }
      pixels = _pixels;
    } else {
      pixels = arena<Uint8>(bytes.length);
    }
    pixels.asTypedList(bytes.length).setAll(0, bytes);
    if (mode & 2 != 0) {
      if (_pool == nullptr) _pool = _poolCreate();
      if (_pool == nullptr) {
        throw StateError('Cannot allocate iOS pixel-buffer pool.');
      }
      return _pooledBgra(
        _pool,
        input.width!,
        input.height!,
        input.bytesPerRow!,
        pixels,
        bytes.length,
        image,
        error,
      );
    }
    return _bgra(
      input.width!,
      input.height!,
      input.bytesPerRow!,
      pixels,
      bytes.length,
      image,
      error,
    );
  }

  /// Releases storage after task teardown. Repeated calls are harmless.
  void close() {
    if (_pool != nullptr) _poolFree(_pool);
    if (_pixels != nullptr) malloc.free(_pixels);
    _pool = nullptr;
    _pixels = nullptr;
    _capacity = 0;
  }
}

/// Retains BGRA and its row stride; the SDK's pixel buffer needs no swizzle.
int createOfficialIosBgraImage(
  VisionImage input,
  Arena arena,
  Pointer<Pointer<Void>> image,
  Pointer<Pointer<Char>> error, {
  IosBgraStorage? storage,
}) {
  if (storage != null) return storage.create(input, arena, image, error);
  final bytes = input.pixels!;
  final pixels = arena<Uint8>(bytes.length);
  pixels.asTypedList(bytes.length).setAll(0, bytes);
  return _bgra(
    input.width!,
    input.height!,
    input.bytesPerRow!,
    pixels,
    bytes.length,
    image,
    error,
  );
}
