import 'dart:typed_data';

import 'package:mediapipe_core/model_store.dart';
import 'package:mediapipe_core/mediapipe_exception.dart';
import 'package:mediapipe_core/platform_interface.dart';

import '../../models.dart' show VisionModels;
import 'vision_types.dart';
export 'vision_types.dart';

/// Shared model ownership and configuration for combined-runtime vision tasks.
abstract base class VisionModelOptions {
  /// Supply exactly one filesystem path or owned model buffer.
  VisionModelOptions({
    this.model,
    String? modelPath,
    Uint8List? modelBytes,
    this.runningMode = RunningMode.image,
    this.delegate = VisionDelegate.cpu,
  }) : _modelPath = modelPath,
       _modelBytes = modelBytes == null
           ? null
           : Uint8List.fromList(modelBytes).asUnmodifiableView() {
    if ([
          model,
          modelPath,
          modelBytes,
        ].where((source) => source != null).length !=
        1) {
      throw ArgumentError(
        'Supply exactly one of model, modelPath and modelBytes.',
      );
    }
    if (modelPath != null &&
        (modelPath.isEmpty || modelPath.contains('\u0000'))) {
      throw ArgumentError.value(modelPath, 'modelPath', 'Invalid path');
    }
    if (modelBytes != null &&
        (modelBytes.isEmpty || modelBytes.length > 0xffffffff)) {
      throw ArgumentError.value(
        modelBytes.length,
        'modelBytes',
        'Invalid model buffer size',
      );
    }
  }

  /// Pinned official model: the app's bundled copy, or a download when
  /// `ModelStore.allowDownloads` is true. Verified against its SHA-256.
  final DownloadAsset? model;

  final String? _modelPath;
  final Uint8List? _modelBytes;
  ModelSource? _resolvedModel;

  /// Resolves a pinned model before handing these options to a runtime.
  Future<void> prepareModel() => _resolveModel();

  Future<void> _resolveModel() async {
    // TODO: Remove this rejection when LIVE_STREAM is split from VIDEO. See
    // RunningMode.liveStream.
    if (runningMode == RunningMode.liveStream) {
      throw UnsupportedError(
        'Live stream mode is not implemented by this runtime.',
      );
    }
    if (model case final selected?) {
      _resolvedModel = await resolvePinnedModel(
        selected,
        family: 'mediapipe_vision',
        registry: VisionModels.byName,
      );
    }
  }

  /// Filesystem path to a model, rather than a Flutter asset key.
  String? get modelPath => _resolvedModel?.path ?? _modelPath;

  /// Owned, read-only model bytes.
  Uint8List? get modelBytes => _resolvedModel?.bytes ?? _modelBytes;

  /// Still-image or timestamped-video processing.
  final RunningMode runningMode;

  /// Requested backend, fixed until disposal.
  final VisionDelegate delegate;
}

/// Region of an image, expressed in normalized input coordinates.
final class VisionRegionOfInterest {
  /// Requires ordered coordinates in [0, 1] with nonzero width and height.
  VisionRegionOfInterest({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  }) {
    if ([left, top, right, bottom].any((v) => !v.isFinite || v < 0 || v > 1) ||
        left >= right ||
        top >= bottom) {
      throw ArgumentError(
        'Region of interest must be nonempty and inside [0, 1].',
      );
    }
  }

  /// Normalized left edge.
  final double left;

  /// Normalized top edge.
  final double top;

  /// Normalized right edge.
  final double right;

  /// Normalized bottom edge.
  final double bottom;
}

/// Category copied from an official classification head.
final class VisionCategory {
  /// Preserve the native score and optional labels.
  const VisionCategory({
    required this.index,
    required this.score,
    this.categoryName,
    this.displayName,
  });

  /// Index in the model's category list, or -1 if unspecified.
  final int index;

  /// Unmodified model score.
  final double score;

  /// Optional category label from model metadata.
  final String? categoryName;

  /// Optional localized display label.
  final String? displayName;
}

/// An immutable classification head.
final class VisionClassifications {
  /// Copy all categories before native results are released.
  VisionClassifications({
    required List<VisionCategory> categories,
    required this.headIndex,
    this.headName,
  }) : categories = List.unmodifiable(categories);

  /// Categories in the native API's order.
  final List<VisionCategory> categories;

  /// Index of the model output head.
  final int headIndex;

  /// Optional model output head name.
  final String? headName;
}

/// An owned float or quantized embedding produced by an image model.
final class VisionEmbedding {
  /// Requires exactly one vector representation and owns a read-only copy.
  VisionEmbedding({
    List<double>? floatEmbedding,
    Uint8List? quantizedEmbedding,
    required this.headIndex,
    this.headName,
  }) : floatEmbedding = floatEmbedding == null
           ? null
           : List.unmodifiable(floatEmbedding),
       quantizedEmbedding = quantizedEmbedding == null
           ? null
           : Uint8List.fromList(quantizedEmbedding).asUnmodifiableView() {
    if ((floatEmbedding == null) == (quantizedEmbedding == null)) {
      throw ArgumentError('Supply exactly one embedding representation.');
    }
  }

  /// Floating-point vector, or null for a quantized result.
  final List<double>? floatEmbedding;

  /// Scalar-quantized bytes, or null for a floating-point result.
  final Uint8List? quantizedEmbedding;

  /// Index of the model output head.
  final int headIndex;

  /// Optional model output head name.
  final String? headName;
}

/// Native or worker failure for a combined-runtime vision task.
final class VisionTaskException extends MediaPipeException {
  /// Preserve diagnostic text and an optional native status code.
  const VisionTaskException(
    super.message, {
    this.statusCode,
    this.gpuUnavailable = false,
  });

  /// MediaPipe/Abseil status code, if this was a native error.
  final int? statusCode;

  /// True when MediaPipe refused [VisionDelegate.gpu] on this machine, for
  /// example on Linux without EGL or with only a software renderer such as
  /// llvmpipe. The package never retries on CPU; create a CPU task instead.
  final bool gpuUnavailable;
  @override
  String toString() => 'VisionTaskException($statusCode): $message';
}
