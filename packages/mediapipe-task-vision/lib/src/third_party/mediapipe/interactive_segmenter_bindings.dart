// Copyright 2026 The MediaPipe Authors.
// Licensed under the Apache License, Version 2.0.
// The stateful Interactive Segmenter API has no published standalone C header,
// so these declarations follow the official mediapipe==1.0.1 Python ctypes
// definitions in vision/interactive_segmenter.py. Base options and images are
// the generated vision bindings' own. ABI sizes and offsets are checked against
// the ctypes definitions in the reference tests.
// ignore_for_file: public_member_api_docs, non_constant_identifier_names
import 'dart:ffi';

import 'vision_bindings.dart' show MpBaseOptions, MpImagePtr;

const _asset = 'package:mediapipe_vision/mediapipe.dylib';

final class MpInteractiveSegmenterOptions extends Struct {
  external MpBaseOptions base_options;
}

final class MpStrokePoint extends Struct {
  @Float()
  external double x;
  @Float()
  external double y;
}

final class MpStroke extends Struct {
  @Int32()
  external int brush_mode;
  external Pointer<MpStrokePoint> points;
  @Uint32()
  external int points_count;
  @Bool()
  external bool is_completed;
}

final class MpStrokes extends Struct {
  external Pointer<MpStroke> strokes;
  @Uint32()
  external int strokes_count;
}

@Native<
  Int32 Function(
    Pointer<MpInteractiveSegmenterOptions>,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpInteractiveSegmenterCreate', assetId: _asset)
external int MpInteractiveSegmenterCreate(
  Pointer<MpInteractiveSegmenterOptions> options,
  Pointer<Pointer<Void>> segmenter,
  Pointer<Pointer<Char>> error,
);

@Native<Int32 Function(Pointer<Void>, MpImagePtr, Pointer<Pointer<Char>>)>(
  symbol: 'MpInteractiveSegmenterSetImage',
  assetId: _asset,
)
external int MpInteractiveSegmenterSetImage(
  Pointer<Void> segmenter,
  MpImagePtr image,
  Pointer<Pointer<Char>> error,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<MpStrokes>,
    Pointer<MpImagePtr>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpInteractiveSegmenterSegment', assetId: _asset)
external int MpInteractiveSegmenterSegment(
  Pointer<Void> segmenter,
  Pointer<MpStrokes> strokes,
  Pointer<MpImagePtr> mask,
  Pointer<Pointer<Char>> error,
);

@Native<Int32 Function(Pointer<Void>, Pointer<Pointer<Char>>)>(
  symbol: 'MpInteractiveSegmenterClose',
  assetId: _asset,
)
external int MpInteractiveSegmenterClose(
  Pointer<Void> segmenter,
  Pointer<Pointer<Char>> error,
);
