// Copyright 2026 The MediaPipe Authors. Licensed under Apache 2.0.
// Adapted from mediapipe==1.0.1 Python ctypes audio/audio_classifier.py,
// components/containers/audio_data_c.py, classification_result_c.py,
// processors/classifier_options_c.py and core/base_options_c.py. Every
// status-returning function takes a trailing error-message argument.
// ignore_for_file: public_member_api_docs
import 'dart:ffi';

/// Core's shared official 1.0.1 runtime, which exports the audio C API.
const _asset = 'package:mediapipe_flutter_core/tasks_1_0_1.dylib';

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

final class MpAudioClassifierOptions extends Struct {
  external MpBaseOptions baseOptions;
  external MpClassifierOptions classifierOptions;

  /// 1 for audio clips, 2 for an audio stream.
  @Int32()
  external int runningMode;

  /// Only used in stream mode.
  external Pointer<Void> resultCallback;
}

final class MpAudioData extends Struct {
  @Int32()
  external int numChannels;
  @Double()
  external double sampleRate;

  /// Interleaved frames: frame 0's channels, then frame 1's, and so on.
  external Pointer<Float> audioData;

  /// Every float, frames times channels.
  @Size()
  external int audioDataSize;
}

final class MpCategory extends Struct {
  @Int32()
  external int index;
  @Float()
  external double score;
  external Pointer<Char> categoryName;
  external Pointer<Char> displayName;
}

final class MpClassifications extends Struct {
  external Pointer<MpCategory> categories;
  @Uint32()
  external int categoriesCount;
  @Int32()
  external int headIndex;
  external Pointer<Char> headName;
}

final class MpClassificationResult extends Struct {
  external Pointer<MpClassifications> classifications;
  @Uint32()
  external int classificationsCount;
  @Int64()
  external int timestampMs;
  @Bool()
  external bool hasTimestampMs;
}

/// One classification result per chunk of the clip.
final class MpAudioClassifierResult extends Struct {
  external Pointer<MpClassificationResult> results;
  @Int32()
  external int resultsCount;
}

@Native<
  Int32 Function(
    Pointer<MpAudioClassifierOptions>,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpAudioClassifierCreate', assetId: _asset)
external int create(
  Pointer<MpAudioClassifierOptions> options,
  Pointer<Pointer<Void>> task,
  Pointer<Pointer<Char>> error,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<MpAudioData>,
    Pointer<MpAudioClassifierResult>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpAudioClassifierClassify', assetId: _asset)
external int classify(
  Pointer<Void> task,
  Pointer<MpAudioData> audio,
  Pointer<MpAudioClassifierResult> result,
  Pointer<Pointer<Char>> error,
);

@Native<Void Function(Pointer<MpAudioClassifierResult>)>(
  symbol: 'MpAudioClassifierCloseResult',
  assetId: _asset,
)
external void closeResult(Pointer<MpAudioClassifierResult> result);

@Native<Int32 Function(Pointer<Void>, Pointer<Pointer<Char>>)>(
  symbol: 'MpAudioClassifierClose',
  assetId: _asset,
)
external int close(Pointer<Void> task, Pointer<Pointer<Char>> error);

@Native<Void Function(Pointer<Char>)>(symbol: 'MpErrorFree', assetId: _asset)
external void errorFree(Pointer<Char> error);
