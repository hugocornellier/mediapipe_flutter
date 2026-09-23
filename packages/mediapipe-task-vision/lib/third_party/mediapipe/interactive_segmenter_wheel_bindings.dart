// Copyright 2026 The MediaPipe Authors.
// Licensed under the Apache License, Version 2.0.
// The functions of interactive_segmenter_bindings.dart, bound to the vision
// package's own runtime. On Linux x64 that runtime is Google's official 1.0.1
// wheel library, which exports the stateful MagicTouch API alongside the other
// vision tasks, so the task needs no second copy of the library.
// ignore_for_file: public_member_api_docs
import 'dart:ffi';

import 'interactive_segmenter_bindings.dart'
    show MpInteractiveSegmenterOptions, MpStrokes;

const _asset = 'package:mediapipe_flutter_vision/vision.dylib';

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
