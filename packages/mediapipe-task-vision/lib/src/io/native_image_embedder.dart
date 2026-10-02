import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:mediapipe_core/mediapipe_core.dart';

import '../../third_party/mediapipe/vision_tasks_bindings.dart' as mp;
import '../capabilities/official_runtime_io.dart';
import '../runner/native_interface.dart';
import '../types/options.dart';
import '../types/results.dart';
import 'native_ios_sdk.dart';
import 'native_vision_image.dart';
import 'native_vision_task.dart';

/// Google's Image Embedder on its worker isolate.
final class NativeImageEmbedder
    implements NativeVisionTask<ImageEmbedderResult> {
  /// Creates the task with the requested delegate and mode.
  NativeImageEmbedder(ImageEmbedderOptions options)
    : _gpu = options.delegate == Delegate.gpu {
    using((arena) {
      final native = arena<mp.ImageEmbedderOptions>();
      setVisionBaseOptions(
        arena,
        native.ref.base_options,
        options,
        officialGpu: true,
      );
      native.ref.running_mode = nativeRunningMode(options.runningMode);
      native.ref.embedder_options
        ..l2_normalize = options.l2Normalize
        ..quantize = options.quantize;
      final output = arena<mp.MpImageEmbedderPtr>();
      checkVisionCreate(
        (error) => mp.MpImageEmbedderCreate(native, output, error),
        gpu: _gpu,
      );
      _task = output.value;
    });
  }
  final bool _gpu;
  mp.MpImageEmbedderPtr _task = nullptr;
  late final IosBgraStorage? _iosBgra =
      hasOfficialIosVisionRuntime() && iosImageStorageMode != 0
      ? IosBgraStorage(iosImageStorageMode)
      : null;

  @override
  ImageEmbedderResult process(VisionTaskInput input) => using((arena) {
    final (source, rotation, timestamp, region) = input;
    final image = createVisionImage(
      arena,
      source,
      expandRgbForGpu: _gpu,
      checked: checkVisionCall,
      iosBgra: _iosBgra,
    );
    try {
      final processing = visionProcessingOptions(arena, rotation, region);
      final result = arena<mp.MpEmbeddingResult>();
      if (timestamp == null) {
        checkVisionCall(
          (error) => mp.MpImageEmbedderEmbedImage(
            _task,
            image,
            processing,
            result,
            error,
          ),
        );
      } else {
        checkVisionCall(
          (error) => mp.MpImageEmbedderEmbedForVideo(
            _task,
            image,
            processing,
            timestamp,
            result,
            error,
          ),
        );
      }
      try {
        return ImageEmbedderResult(
          embeddings: [
            for (var i = 0; i < result.ref.embeddings_count; i++)
              copyVisionEmbedding(result.ref.embeddings[i]),
          ],
          imageWidth: mp.MpImageGetWidth(image),
          imageHeight: mp.MpImageGetHeight(image),
          timestampMilliseconds: timestamp,
        );
      } finally {
        mp.MpImageEmbedderCloseResult(result);
      }
    } finally {
      mp.MpImageFree(image);
    }
  });

  @override
  void close() {
    if (_task == nullptr) return;
    final task = _task;
    _task = nullptr;
    try {
      checkVisionCall((error) => mp.MpImageEmbedderClose(task, error));
    } finally {
      _iosBgra?.close();
    }
  }
}
