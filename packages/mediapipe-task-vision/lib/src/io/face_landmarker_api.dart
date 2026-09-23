import 'dart:ffi';
import 'dart:io';

import '../../third_party/mediapipe/face_landmarker_bindings.dart' as mp;
import '../capabilities/official_runtime_io.dart';

/// Face Landmarker's C API, from whichever asset serves it.
///
/// Google's macOS monolith registers its graphs in a registry that dyld shares
/// between loaded images, so a process may load it only once: a second copy
/// aborts on its first duplicate graph registration. When an app selects the
/// monolith for Face Landmarker and for a task on the shared vision asset
/// (Hand, Pose), the build hook bundles it once, as that shared asset, and Face
/// Landmarker calls the same C functions through it.
final class FaceLandmarkerApi {
  const FaceLandmarkerApi._({
    required this.create,
    required this.imageFromFile,
    required this.imageFromData,
    required this.detectImage,
    required this.detectForVideo,
    required this.imageWidth,
    required this.imageHeight,
    required this.closeResult,
    required this.imageFree,
    required this.close,
    required this.errorFree,
  });

  /// `MpFaceLandmarkerCreate`.
  final mp.MpStatus Function(
    Pointer<mp.MpFaceLandmarkerOptions>,
    Pointer<mp.MpFaceLandmarkerPtr>,
    Pointer<Pointer<Char>>,
  )
  create;

  /// `MpImageCreateFromFile`.
  final mp.MpStatus Function(
    Pointer<Char>,
    Pointer<mp.MpImagePtr>,
    Pointer<Pointer<Char>>,
  )
  imageFromFile;

  /// `MpImageCreateFromUint8Data`.
  final mp.MpStatus Function(
    mp.MpImageFormat,
    int,
    int,
    Pointer<Uint8>,
    int,
    Pointer<mp.MpImagePtr>,
    Pointer<Pointer<Char>>,
  )
  imageFromData;

  /// `MpFaceLandmarkerDetectImage`.
  final mp.MpStatus Function(
    mp.MpFaceLandmarkerPtr,
    mp.MpImagePtr,
    Pointer<mp.MpImageProcessingOptions>,
    Pointer<mp.MpFaceLandmarkerResult>,
    Pointer<Pointer<Char>>,
  )
  detectImage;

  /// `MpFaceLandmarkerDetectForVideo`.
  final mp.MpStatus Function(
    mp.MpFaceLandmarkerPtr,
    mp.MpImagePtr,
    Pointer<mp.MpImageProcessingOptions>,
    int,
    Pointer<mp.MpFaceLandmarkerResult>,
    Pointer<Pointer<Char>>,
  )
  detectForVideo;

  /// `MpImageGetWidth`.
  final int Function(mp.MpImagePtr) imageWidth;

  /// `MpImageGetHeight`.
  final int Function(mp.MpImagePtr) imageHeight;

  /// `MpFaceLandmarkerCloseResult`.
  final void Function(Pointer<mp.MpFaceLandmarkerResult>) closeResult;

  /// `MpImageFree`.
  final void Function(mp.MpImagePtr) imageFree;

  /// `MpFaceLandmarkerClose`.
  final mp.MpStatus Function(mp.MpFaceLandmarkerPtr, Pointer<Pointer<Char>>)
  close;

  /// `MpErrorFree`.
  final void Function(Pointer<Char>) errorFree;

  /// The generated bindings, on Face Landmarker's own asset.
  static const _own = FaceLandmarkerApi._(
    create: mp.MpFaceLandmarkerCreate,
    imageFromFile: mp.MpImageCreateFromFile,
    imageFromData: mp.MpImageCreateFromUint8Data,
    detectImage: mp.MpFaceLandmarkerDetectImage,
    detectForVideo: mp.MpFaceLandmarkerDetectForVideo,
    imageWidth: mp.MpImageGetWidth,
    imageHeight: mp.MpImageGetHeight,
    closeResult: mp.MpFaceLandmarkerCloseResult,
    imageFree: mp.MpImageFree,
    close: mp.MpFaceLandmarkerClose,
    errorFree: mp.MpErrorFree,
  );

  /// The same functions on the shared vision asset.
  static const _shared = FaceLandmarkerApi._(
    create: _sharedCreate,
    imageFromFile: _sharedImageFromFile,
    imageFromData: _sharedImageFromData,
    detectImage: _sharedDetectImage,
    detectForVideo: _sharedDetectForVideo,
    imageWidth: _sharedImageWidth,
    imageHeight: _sharedImageHeight,
    closeResult: _sharedCloseResult,
    imageFree: _sharedImageFree,
    close: _sharedClose,
    errorFree: _sharedErrorFree,
  );

  /// The API this process uses: Face Landmarker's own asset, or on macOS the
  /// shared asset when the build bundled Google's monolith there instead.
  static final FaceLandmarkerApi current =
      Platform.isMacOS && !_ownAssetLoads() && hasOfficialMacosLandmarkRuntime()
      ? _shared
      : _own;

  // Loading the own asset is the next step anyway when it is bundled.
  static bool _ownAssetLoads() {
    try {
      return Native.addressOf<NativeFunction<Void Function(Pointer<Char>)>>(
            mp.MpErrorFree,
          ) !=
          nullptr;
    } on ArgumentError {
      return false;
    }
  }
}

const _vision = 'package:mediapipe_flutter_vision/vision.dylib';

@Native<
  UnsignedInt Function(
    Pointer<mp.MpFaceLandmarkerOptions>,
    Pointer<mp.MpFaceLandmarkerPtr>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpFaceLandmarkerCreate', assetId: _vision)
external int _create(
  Pointer<mp.MpFaceLandmarkerOptions> options,
  Pointer<mp.MpFaceLandmarkerPtr> landmarker,
  Pointer<Pointer<Char>> error,
);

mp.MpStatus _sharedCreate(
  Pointer<mp.MpFaceLandmarkerOptions> options,
  Pointer<mp.MpFaceLandmarkerPtr> landmarker,
  Pointer<Pointer<Char>> error,
) => mp.MpStatus.fromValue(_create(options, landmarker, error));

@Native<
  UnsignedInt Function(
    Pointer<Char>,
    Pointer<mp.MpImagePtr>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpImageCreateFromFile', assetId: _vision)
external int _imageFromFile(
  Pointer<Char> fileName,
  Pointer<mp.MpImagePtr> out,
  Pointer<Pointer<Char>> error,
);

mp.MpStatus _sharedImageFromFile(
  Pointer<Char> fileName,
  Pointer<mp.MpImagePtr> out,
  Pointer<Pointer<Char>> error,
) => mp.MpStatus.fromValue(_imageFromFile(fileName, out, error));

@Native<
  UnsignedInt Function(
    UnsignedInt,
    Int,
    Int,
    Pointer<Uint8>,
    Int,
    Pointer<mp.MpImagePtr>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpImageCreateFromUint8Data', assetId: _vision)
external int _imageFromData(
  int format,
  int width,
  int height,
  Pointer<Uint8> pixels,
  int length,
  Pointer<mp.MpImagePtr> out,
  Pointer<Pointer<Char>> error,
);

mp.MpStatus _sharedImageFromData(
  mp.MpImageFormat format,
  int width,
  int height,
  Pointer<Uint8> pixels,
  int length,
  Pointer<mp.MpImagePtr> out,
  Pointer<Pointer<Char>> error,
) => mp.MpStatus.fromValue(
  _imageFromData(format.value, width, height, pixels, length, out, error),
);

@Native<
  UnsignedInt Function(
    mp.MpFaceLandmarkerPtr,
    mp.MpImagePtr,
    Pointer<mp.MpImageProcessingOptions>,
    Pointer<mp.MpFaceLandmarkerResult>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpFaceLandmarkerDetectImage', assetId: _vision)
external int _detectImage(
  mp.MpFaceLandmarkerPtr landmarker,
  mp.MpImagePtr image,
  Pointer<mp.MpImageProcessingOptions> options,
  Pointer<mp.MpFaceLandmarkerResult> result,
  Pointer<Pointer<Char>> error,
);

mp.MpStatus _sharedDetectImage(
  mp.MpFaceLandmarkerPtr landmarker,
  mp.MpImagePtr image,
  Pointer<mp.MpImageProcessingOptions> options,
  Pointer<mp.MpFaceLandmarkerResult> result,
  Pointer<Pointer<Char>> error,
) => mp.MpStatus.fromValue(
  _detectImage(landmarker, image, options, result, error),
);

@Native<
  UnsignedInt Function(
    mp.MpFaceLandmarkerPtr,
    mp.MpImagePtr,
    Pointer<mp.MpImageProcessingOptions>,
    Int64,
    Pointer<mp.MpFaceLandmarkerResult>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpFaceLandmarkerDetectForVideo', assetId: _vision)
external int _detectForVideo(
  mp.MpFaceLandmarkerPtr landmarker,
  mp.MpImagePtr image,
  Pointer<mp.MpImageProcessingOptions> options,
  int timestamp,
  Pointer<mp.MpFaceLandmarkerResult> result,
  Pointer<Pointer<Char>> error,
);

mp.MpStatus _sharedDetectForVideo(
  mp.MpFaceLandmarkerPtr landmarker,
  mp.MpImagePtr image,
  Pointer<mp.MpImageProcessingOptions> options,
  int timestamp,
  Pointer<mp.MpFaceLandmarkerResult> result,
  Pointer<Pointer<Char>> error,
) => mp.MpStatus.fromValue(
  _detectForVideo(landmarker, image, options, timestamp, result, error),
);

@Native<Int Function(mp.MpImagePtr)>(
  symbol: 'MpImageGetWidth',
  assetId: _vision,
)
external int _sharedImageWidth(mp.MpImagePtr image);

@Native<Int Function(mp.MpImagePtr)>(
  symbol: 'MpImageGetHeight',
  assetId: _vision,
)
external int _sharedImageHeight(mp.MpImagePtr image);

@Native<Void Function(Pointer<mp.MpFaceLandmarkerResult>)>(
  symbol: 'MpFaceLandmarkerCloseResult',
  assetId: _vision,
)
external void _sharedCloseResult(Pointer<mp.MpFaceLandmarkerResult> result);

@Native<Void Function(mp.MpImagePtr)>(symbol: 'MpImageFree', assetId: _vision)
external void _sharedImageFree(mp.MpImagePtr image);

@Native<UnsignedInt Function(mp.MpFaceLandmarkerPtr, Pointer<Pointer<Char>>)>(
  symbol: 'MpFaceLandmarkerClose',
  assetId: _vision,
)
external int _close(
  mp.MpFaceLandmarkerPtr landmarker,
  Pointer<Pointer<Char>> error,
);

mp.MpStatus _sharedClose(
  mp.MpFaceLandmarkerPtr landmarker,
  Pointer<Pointer<Char>> error,
) => mp.MpStatus.fromValue(_close(landmarker, error));

@Native<Void Function(Pointer<Char>)>(symbol: 'MpErrorFree', assetId: _vision)
external void _sharedErrorFree(Pointer<Char> error);
