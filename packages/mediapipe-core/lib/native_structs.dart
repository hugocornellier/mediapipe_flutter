// Copyright 2026 The MediaPipe Authors. Licensed under Apache 2.0.
// Adapted from mediapipe==1.0.1 Python ctypes: core/base_options_c.py,
// components/processors/classifier_options_c.py and
// components/containers/classification_result_c.py.
// ignore_for_file: public_member_api_docs

/// Google's MediaPipe C structs that more than one family binds, from the
/// release core pins for every family (`family_runtimes.dart`). For the
/// family packages' FFI bindings, whose ABI tests check every size and field
/// offset against Google's wheel; not for applications.
library;

import 'dart:ffi';

/// `MpBaseOptions`: the model, delegate and host every task's options embed.
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

/// `MpClassifierOptions`: the classifiers' result filtering.
final class MpClassifierOptions extends Struct {
  external Pointer<Char> displayNamesLocale;
  @Int32()
  external int maxResults;
  @Float()
  external double scoreThreshold;
  external Pointer<Pointer<Char>> categoryAllowlist;
  @Uint32()
  external int categoryAllowlistCount;
  external Pointer<Pointer<Char>> categoryDenylist;
  @Uint32()
  external int categoryDenylistCount;
}

/// `MpCategory`: one class and its score.
final class MpCategory extends Struct {
  @Int32()
  external int index;
  @Float()
  external double score;
  external Pointer<Char> categoryName;
  external Pointer<Char> displayName;
}

/// `MpClassifications`: one classifier head's categories.
final class MpClassifications extends Struct {
  external Pointer<MpCategory> categories;
  @Uint32()
  external int categoriesCount;
  @Int32()
  external int headIndex;
  external Pointer<Char> headName;
}

/// `MpClassificationResult`: every head, with a timestamp.
final class MpClassificationResult extends Struct {
  external Pointer<MpClassifications> classifications;
  @Uint32()
  external int classificationsCount;
  @Int64()
  external int timestampMs;
  @Bool()
  external bool hasTimestampMs;
}
