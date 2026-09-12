// Copyright 2026 The MediaPipe Authors.
// Licensed under the Apache License, Version 2.0.
// Dart declarations adapted from the official mediapipe==1.0.1 Python ctypes
// definitions: core/base_options_c.py, vision/interactive_segmenter.py and
// vision/core/image.py. The stateful API has no published standalone C header.
// ABI sizes/offsets are checked against those definitions in the reference tests.
// ignore_for_file: public_member_api_docs
import 'dart:ffi';

const _asset = 'package:mediapipe_flutter_vision/interactive_segmenter.dylib';

final class MpBaseOptions extends Struct {
  external Pointer<Char> modelAssetBuffer;
  @Uint32()
  external int modelAssetBufferCount;
  external Pointer<Char> modelAssetPath;
  @Int32()
  external int fileDescriptor;
  @Int32()
  external int delegate;
  @Int32()
  external int hostEnvironment;
  @Int32()
  external int hostSystem;
  external Pointer<Char> hostVersion;
  external Pointer<Char> caBundlePath;
  external Pointer<Char> appId;
  external Pointer<Char> appVersion;
}

final class MpInteractiveSegmenterOptions extends Struct {
  external MpBaseOptions baseOptions;
}

final class MpStrokePoint extends Struct {
  @Float()
  external double x;
  @Float()
  external double y;
}

final class MpStroke extends Struct {
  @Int32()
  external int brushMode;
  external Pointer<MpStrokePoint> points;
  @Uint32()
  external int pointsCount;
  @Bool()
  external bool isCompleted;
}

final class MpStrokes extends Struct {
  external Pointer<MpStroke> strokes;
  @Uint32()
  external int strokesCount;
}

@Native<
  Int32 Function(
    Pointer<MpInteractiveSegmenterOptions>,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpInteractiveSegmenterCreate', assetId: _asset)
external int create(
  Pointer<MpInteractiveSegmenterOptions> options,
  Pointer<Pointer<Void>> output,
  Pointer<Pointer<Char>> error,
);

@Native<Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Pointer<Char>>)>(
  symbol: 'MpInteractiveSegmenterSetImage',
  assetId: _asset,
)
external int setImage(
  Pointer<Void> task,
  Pointer<Void> image,
  Pointer<Pointer<Char>> error,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<MpStrokes>,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpInteractiveSegmenterSegment', assetId: _asset)
external int segment(
  Pointer<Void> task,
  Pointer<MpStrokes> strokes,
  Pointer<Pointer<Void>> mask,
  Pointer<Pointer<Char>> error,
);

@Native<Int32 Function(Pointer<Void>, Pointer<Pointer<Char>>)>(
  symbol: 'MpInteractiveSegmenterClose',
  assetId: _asset,
)
external int close(Pointer<Void> task, Pointer<Pointer<Char>> error);

@Native<
  Int32 Function(Pointer<Char>, Pointer<Pointer<Void>>, Pointer<Pointer<Char>>)
>(symbol: 'MpImageCreateFromFile', assetId: _asset)
external int imageFromFile(
  Pointer<Char> path,
  Pointer<Pointer<Void>> image,
  Pointer<Pointer<Char>> error,
);

@Native<
  Int32 Function(
    Int32,
    Int32,
    Int32,
    Pointer<Uint8>,
    Int32,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpImageCreateFromUint8Data', assetId: _asset)
external int imageFromPixels(
  int format,
  int width,
  int height,
  Pointer<Uint8> pixels,
  int count,
  Pointer<Pointer<Void>> image,
  Pointer<Pointer<Char>> error,
);

@Native<
  Int32 Function(Pointer<Void>, Pointer<Pointer<Float>>, Pointer<Pointer<Char>>)
>(symbol: 'MpImageDataFloat32', assetId: _asset)
external int imageData(
  Pointer<Void> image,
  Pointer<Pointer<Float>> data,
  Pointer<Pointer<Char>> error,
);

@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'MpImageGetWidth',
  assetId: _asset,
)
external int imageWidth(Pointer<Void> image);

@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'MpImageGetHeight',
  assetId: _asset,
)
external int imageHeight(Pointer<Void> image);

@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'MpImageGetChannels',
  assetId: _asset,
)
external int imageChannels(Pointer<Void> image);

@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'MpImageGetByteDepth',
  assetId: _asset,
)
external int imageByteDepth(Pointer<Void> image);

@Native<Void Function(Pointer<Void>)>(symbol: 'MpImageFree', assetId: _asset)
external void imageFree(Pointer<Void> image);

@Native<Void Function(Pointer<Char>)>(symbol: 'MpErrorFree', assetId: _asset)
external void errorFree(Pointer<Char> error);
