import 'dart:ffi';
import 'dart:io';

import '../../third_party/mediapipe/face_landmarker_bindings.dart' as mp;
import '../capabilities/official_runtime_io.dart';

/// Face Landmarker's C API, from whichever asset serves it.
///
/// Google's macOS engine registers its graphs in a registry that dyld shares
/// between loaded images, so a process may load it only once: a second copy
/// aborts on its first duplicate graph registration. When core bundles that
/// engine for the other tasks, the build hook bundles no Face Landmarker
/// library of its own, and Face Landmarker calls the same C functions through
/// core's asset.
final class FaceLandmarkerApi {
  const FaceLandmarkerApi._({
    required this.usesEngine,
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

  /// Whether these functions are core's engine's rather than Face
  /// Landmarker's own asset's.
  final bool usesEngine;

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
    usesEngine: false,
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

  /// The same functions on core's engine asset.
  static const _shared = FaceLandmarkerApi._(
    usesEngine: true,
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

  /// The API this process uses: on macOS core's engine whenever the build
  /// bundled it, otherwise Face Landmarker's own asset.
  ///
  /// The build bundles exactly one of them (hook/build.dart leaves the own
  /// asset out when the engine is on), so this follows the build rather than
  /// probing the own asset. A probe misleads: Dart resolves a missing asset's
  /// symbols from whatever the process has loaded, and Face Detector's macOS
  /// library exports MpErrorFree and the MpImage functions as well.
  static final FaceLandmarkerApi current =
      Platform.isMacOS && hasMacosTasksRuntime() ? _shared : _own;
}

const _engine = 'package:mediapipe_core/mediapipe.dylib';

@Native<
  UnsignedInt Function(
    Pointer<mp.MpFaceLandmarkerOptions>,
    Pointer<mp.MpFaceLandmarkerPtr>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpFaceLandmarkerCreate', assetId: _engine)
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
>(symbol: 'MpImageCreateFromFile', assetId: _engine)
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
>(symbol: 'MpImageCreateFromUint8Data', assetId: _engine)
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
>(symbol: 'MpFaceLandmarkerDetectImage', assetId: _engine)
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
>(symbol: 'MpFaceLandmarkerDetectForVideo', assetId: _engine)
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
  assetId: _engine,
)
external int _sharedImageWidth(mp.MpImagePtr image);

@Native<Int Function(mp.MpImagePtr)>(
  symbol: 'MpImageGetHeight',
  assetId: _engine,
)
external int _sharedImageHeight(mp.MpImagePtr image);

@Native<Void Function(Pointer<mp.MpFaceLandmarkerResult>)>(
  symbol: 'MpFaceLandmarkerCloseResult',
  assetId: _engine,
)
external void _sharedCloseResult(Pointer<mp.MpFaceLandmarkerResult> result);

@Native<Void Function(mp.MpImagePtr)>(symbol: 'MpImageFree', assetId: _engine)
external void _sharedImageFree(mp.MpImagePtr image);

@Native<UnsignedInt Function(mp.MpFaceLandmarkerPtr, Pointer<Pointer<Char>>)>(
  symbol: 'MpFaceLandmarkerClose',
  assetId: _engine,
)
external int _close(
  mp.MpFaceLandmarkerPtr landmarker,
  Pointer<Pointer<Char>> error,
);

mp.MpStatus _sharedClose(
  mp.MpFaceLandmarkerPtr landmarker,
  Pointer<Pointer<Char>> error,
) => mp.MpStatus.fromValue(_close(landmarker, error));

@Native<Void Function(Pointer<Char>)>(symbol: 'MpErrorFree', assetId: _engine)
external void _sharedErrorFree(Pointer<Char> error);
