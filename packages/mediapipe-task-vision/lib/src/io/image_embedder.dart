import 'dart:ffi';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';

import '../../capabilities.dart';

import '../../third_party/mediapipe/vision_tasks_bindings.dart' as mp;
import '../interface/image_embedder_types.dart';
import 'native_vision_image.dart';
import 'native_vision_task.dart';
import 'vision_task_worker.dart';

/// Official Image Embedder with owned vectors and serialized native inference.
final class ImageEmbedder {
  ImageEmbedder._(this._worker, this.delegate);
  final VisionTaskWorker<ImageEmbedderResult> _worker;

  /// Requested backend, fixed until disposal.
  final VisionDelegate delegate;

  /// Mode selected when creating this task.
  VisionRunningMode get runningMode => _worker.runningMode;

  /// Load a model and initialize the official graph off the calling isolate.
  static Future<ImageEmbedder> create(ImageEmbedderOptions options) async {
    final capabilities = await queryImageTaskCapabilities();
    if (!capabilities.supportedDelegates.contains(options.delegate)) {
      throw UnsupportedError(
        capabilities.unavailableReasons[options.delegate]!,
      );
    }
    return ImageEmbedder._(
      await VisionTaskWorker.create(
        options,
        _createNative,
        'MediaPipe Image Embedder',
      ),
      options.delegate,
    );
  }

  /// Embed a still image or normalized region using official preprocessing.
  Future<ImageEmbedderResult> embedImage(
    VisionImage image, {
    int rotationDegrees = 0,
    VisionRegionOfInterest? regionOfInterest,
  }) => _worker.processImage(image, rotationDegrees, regionOfInterest);

  /// Embed a video frame with a strictly increasing millisecond timestamp.
  Future<ImageEmbedderResult> embedForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
    VisionRegionOfInterest? regionOfInterest,
  }) => _worker.processVideo(
    image,
    rotationDegrees,
    timestampMilliseconds,
    regionOfInterest,
  );

  /// Compare equally sized float vectors or equally sized quantized vectors.
  ///
  /// Scalar-quantized bytes encode signed int8 values, as in the official task.
  /// Mixed representations, empty/zero vectors and nonfinite values are rejected.
  static double cosineSimilarity(
    VisionEmbedding first,
    VisionEmbedding second,
  ) {
    final floating = first.floatEmbedding != null;
    if (floating != (second.floatEmbedding != null)) {
      throw ArgumentError('Embedding representations must match.');
    }
    final left = floating
        ? first.floatEmbedding!
        : first.quantizedEmbedding!
              .map((v) => v.toSigned(8).toDouble())
              .toList();
    final right = floating
        ? second.floatEmbedding!
        : second.quantizedEmbedding!
              .map((v) => v.toSigned(8).toDouble())
              .toList();
    if (left.isEmpty || left.length != right.length) {
      throw ArgumentError('Embedding dimensions must be nonzero and equal.');
    }
    var dot = 0.0;
    var normLeft = 0.0;
    var normRight = 0.0;
    for (var i = 0; i < left.length; i++) {
      if (!left[i].isFinite || !right[i].isFinite) {
        throw ArgumentError('Embeddings must contain finite values.');
      }
      dot += left[i] * right[i];
      normLeft += left[i] * left[i];
      normRight += right[i] * right[i];
    }
    if (normLeft == 0 ||
        normRight == 0 ||
        !dot.isFinite ||
        !normLeft.isFinite ||
        !normRight.isFinite) {
      throw ArgumentError('Embedding norms must be finite and nonzero.');
    }
    return (dot / math.sqrt(normLeft) / math.sqrt(normRight)).clamp(-1.0, 1.0);
  }

  /// Drain queued requests and release native resources exactly once.
  Future<void> dispose() => _worker.dispose();
}

NativeVisionTask<ImageEmbedderResult> _createNative(
  ImageEmbedderOptions options,
) => _NativeImageEmbedder(options);

final class _NativeImageEmbedder
    implements NativeVisionTask<ImageEmbedderResult> {
  _NativeImageEmbedder(ImageEmbedderOptions options)
    : _gpu = options.delegate == VisionDelegate.gpu {
    using((arena) {
      final native = arena<mp.ImageEmbedderOptions>();
      setVisionBaseOptions(arena, native.ref.base_options, options);
      native.ref.running_mode = nativeVisionRunningMode(options.runningMode);
      native.ref.embedder_options
        ..l2_normalize = options.l2Normalize
        ..quantize = options.quantize;
      final output = arena<mp.MpImageEmbedderPtr>();
      checkVisionCall(
        (error) => mp.MpImageEmbedderCreate(native, output, error),
      );
      _task = output.value;
    });
  }
  final bool _gpu;
  mp.MpImageEmbedderPtr _task = nullptr;

  @override
  ImageEmbedderResult process(VisionTaskInput input) => using((arena) {
    final (source, rotation, timestamp, region) = input;
    final image = createVisionImage(
      arena,
      source,
      expandRgbForGpu: _gpu,
      checked: checkVisionCall,
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
    checkVisionCall((error) => mp.MpImageEmbedderClose(task, error));
  }
}
