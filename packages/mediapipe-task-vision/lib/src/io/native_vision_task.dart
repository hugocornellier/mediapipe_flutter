import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../third_party/mediapipe/vision_tasks_bindings.dart' as mp;
import '../interface/landmark_task_types.dart';
import '../interface/segmenter_task_types.dart';
import 'native_desktop_runtime.dart';
import 'native_vision_image.dart';

/// Initialize the shared base options with owned model bytes or a model path.
void setVisionBaseOptions(
  Arena arena,
  mp.MpBaseOptions base,
  VisionModelOptions options,
) {
  if (!Platform.isMacOS && options.delegate == VisionDelegate.gpu) {
    throw UnsupportedError('GPU vision inference is validated on macOS only.');
  }
  loadOfficialDesktopRuntime();
  base.file_descriptor = -1;
  base.delegate = options.delegate == VisionDelegate.gpu
      ? mp.MpDelegate.MP_DELEGATE_GPU
      : mp.MpDelegate.MP_DELEGATE_CPU;
  base.host_system = Platform.isLinux
      ? mp.MpHostSystem.MP_HOST_SYSTEM_LINUX
      : Platform.isWindows
      ? mp.MpHostSystem.MP_HOST_SYSTEM_WINDOWS
      : Platform.isIOS
      ? mp.MpHostSystem.MP_HOST_SYSTEM_IOS
      : mp.MpHostSystem.MP_HOST_SYSTEM_MAC;
  if (options.modelPath case final path?) {
    base.model_asset_path = path.toNativeUtf8(allocator: arena).cast();
  }
  if (options.modelBytes case final bytes?) {
    final buffer = arena<Uint8>(bytes.length);
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    base.model_asset_buffer = buffer.cast();
    base.model_asset_buffer_count = bytes.length;
  }
}

/// Convert the public running mode into the native task enum.
mp.MpRunningMode nativeVisionRunningMode(VisionRunningMode mode) =>
    mode == VisionRunningMode.video
    ? mp.MpRunningMode.MP_RUNNING_MODE_VIDEO
    : mp.MpRunningMode.MP_RUNNING_MODE_IMAGE;

/// Populate native rotation and optional normalized region of interest.
Pointer<mp.MpImageProcessingOptions> visionProcessingOptions(
  Arena arena,
  int rotation,
  VisionRegionOfInterest? region,
) {
  final options = arena<mp.MpImageProcessingOptions>();
  options.ref.rotation_degrees = rotation;
  if (region != null) {
    options.ref.has_region_of_interest = 1;
    options.ref.region_of_interest
      ..left = region.left
      ..top = region.top
      ..right = region.right
      ..bottom = region.bottom;
  }
  return options;
}

/// Copy native category labels and scores before closing the result.
VisionCategory copyVisionCategory(mp.MpCategory category) => VisionCategory(
  index: category.index,
  score: category.score,
  categoryName: nativeString(category.category_name),
  displayName: nativeString(category.display_name),
);

/// Copy every head and category into immutable Dart values.
List<VisionClassifications> copyVisionClassifications(
  mp.MpClassificationResult result,
) => [
  for (var i = 0; i < result.classifications_count; i++)
    VisionClassifications(
      headIndex: result.classifications[i].head_index,
      headName: nativeString(result.classifications[i].head_name),
      categories: [
        for (var j = 0; j < result.classifications[i].categories_count; j++)
          copyVisionCategory(result.classifications[i].categories[j]),
      ],
    ),
];

/// Copy a native embedding, preserving quantized bytes without sign conversion.
VisionEmbedding copyVisionEmbedding(mp.MpEmbedding value) => VisionEmbedding(
  headIndex: value.head_index,
  headName: nativeString(value.head_name),
  floatEmbedding: value.float_embedding == nullptr
      ? null
      : value.float_embedding.asTypedList(value.values_count),
  quantizedEmbedding: value.quantized_embedding == nullptr
      ? null
      : value.quantized_embedding.cast<Uint8>().asTypedList(value.values_count),
);

/// Release native errors and throw an owned diagnostic on non-OK status.
void checkVisionCall(mp.MpStatus Function(Pointer<Pointer<Char>>) call) =>
    checkedCall(
      call,
      onError: (message, status) =>
          VisionTaskException(message, statusCode: status),
    );

/// Copy metadata option strings into the task creation arena.
Pointer<Pointer<Char>> visionOptionStrings(Arena arena, List<String> values) {
  if (values.isEmpty) return nullptr;
  final array = arena<Pointer<Char>>(values.length);
  for (var i = 0; i < values.length; i++) {
    array[i] = values[i].toNativeUtf8(allocator: arena).cast();
  }
  return array;
}

/// Own every category in each hand's classification result.
///
/// [index] overrides the native index for heads whose raw value carries no
/// meaning, matching how the official bindings report them.
List<List<VisionCategory>> copyVisionCategories(
  Pointer<mp.MpCategories> values,
  int count, {
  int? index,
}) => [
  for (var i = 0; i < count; i++)
    [
      for (var j = 0; j < values[i].categories_count; j++)
        if (index == null)
          copyVisionCategory(values[i].categories[j])
        else
          VisionCategory(
            index: index,
            score: values[i].categories[j].score,
            categoryName: nativeString(values[i].categories[j].category_name),
            displayName: nativeString(values[i].categories[j].display_name),
          ),
    ],
];

/// Own normalized landmarks including optional confidence metadata.
List<VisionLandmark> copyVisionNormalizedLandmarks(
  mp.MpNormalizedLandmarks values,
) => [
  for (var i = 0; i < values.landmarks_count; i++)
    VisionLandmark(
      x: values.landmarks[i].x,
      y: values.landmarks[i].y,
      z: values.landmarks[i].z,
      visibility: values.landmarks[i].has_visibility
          ? values.landmarks[i].visibility
          : null,
      presence: values.landmarks[i].has_presence
          ? values.landmarks[i].presence
          : null,
      name: nativeString(values.landmarks[i].name),
    ),
];

/// Own world landmarks including optional confidence metadata.
List<VisionLandmark> copyVisionWorldLandmarks(mp.MpLandmarks values) => [
  for (var i = 0; i < values.landmarks_count; i++)
    VisionLandmark(
      x: values.landmarks[i].x,
      y: values.landmarks[i].y,
      z: values.landmarks[i].z,
      visibility: values.landmarks[i].has_visibility
          ? values.landmarks[i].visibility
          : null,
      presence: values.landmarks[i].has_presence
          ? values.landmarks[i].presence
          : null,
      name: nativeString(values.landmarks[i].name),
    ),
];

/// Read and copy a single-channel float32 mask, including padded native rows.
SegmentationMask copyVisionConfidenceMask(Arena arena, mp.MpImagePtr image) {
  final width = mp.MpImageGetWidth(image);
  final height = mp.MpImageGetHeight(image);
  if (width < 1 ||
      height < 1 ||
      mp.MpImageGetChannels(image) != 1 ||
      mp.MpImageGetByteDepth(image) != 4) {
    throw const VisionTaskException(
      'Native result is not a float32 confidence mask.',
    );
  }
  final data = arena<Pointer<Float>>();
  // The pinned 1.0.0 float accessor aborts while copying padded rows because
  // its ImageFrame copy selects the uint8 overload. Use the checked scalar
  // API for those images, preserving dimensions and every float32 value.
  if (!mp.MpImageIsContiguous(image)) {
    final values = Float32List(width * height);
    final position = arena<Int>(2);
    final value = arena<Float>();
    for (var y = 0; y < height; y++) {
      position[0] = y;
      for (var x = 0; x < width; x++) {
        position[1] = x;
        checkVisionCall(
          (error) =>
              mp.MpImageGetValueFloat32(image, position, 2, value, error),
        );
        values[y * width + x] = value.value;
      }
    }
    return SegmentationMask(width: width, height: height, confidence: values);
  }
  checkVisionCall((error) => mp.MpImageDataFloat32(image, data, error));
  if (data.value == nullptr) {
    throw const VisionTaskException('Native mask data is missing.');
  }
  return SegmentationMask(
    width: width,
    height: height,
    confidence: data.value.asTypedList(width * height),
  );
}

/// Read and copy a single-channel uint8 category mask.
///
/// The contiguous-copy path is correct for uint8 images, unlike the float32
/// accessor in UP-003, so the official accessor handles padded rows here.
CategoryMask copyVisionCategoryMask(Arena arena, mp.MpImagePtr image) {
  final width = mp.MpImageGetWidth(image);
  final height = mp.MpImageGetHeight(image);
  if (width < 1 ||
      height < 1 ||
      mp.MpImageGetChannels(image) != 1 ||
      mp.MpImageGetByteDepth(image) != 1) {
    throw const VisionTaskException(
      'Native result is not a uint8 category mask.',
    );
  }
  final data = arena<Pointer<Uint8>>();
  checkVisionCall((error) => mp.MpImageDataUint8(image, data, error));
  if (data.value == nullptr) {
    throw const VisionTaskException('Native mask data is missing.');
  }
  return CategoryMask(
    width: width,
    height: height,
    categories: data.value.asTypedList(width * height),
  );
}

/// Own every mask and quality score in a shared segmentation result.
SegmentationResult copyVisionSegmentation(
  Arena arena,
  mp.MpImageSegmenterResult result,
  mp.MpImagePtr image,
  int? timestamp, {
  List<String> labels = const [],
}) => SegmentationResult(
  labels: labels,
  confidenceMasks: result.confidence_masks_count == 0
      ? null
      : [
          for (var i = 0; i < result.confidence_masks_count; i++)
            copyVisionConfidenceMask(arena, result.confidence_masks[i]),
        ],
  categoryMask: result.has_category_mask == 0
      ? null
      : copyVisionCategoryMask(arena, result.category_mask),
  qualityScores: result.quality_scores == nullptr
      ? null
      : result.quality_scores.asTypedList(result.quality_scores_count),
  imageWidth: mp.MpImageGetWidth(image),
  imageHeight: mp.MpImageGetHeight(image),
  timestampMilliseconds: timestamp,
);

/// Populate native canned/custom gesture classification filters.
void setVisionGestureClassifier(
  Arena arena,
  mp.MpClassifierOptions output,
  GestureClassifierOptions options,
) {
  output
    ..max_results = options.maxResults
    ..score_threshold = options.scoreThreshold
    ..category_allowlist = visionOptionStrings(arena, options.categoryAllowlist)
    ..category_allowlist_count = options.categoryAllowlist.length
    ..category_denylist = visionOptionStrings(arena, options.categoryDenylist)
    ..category_denylist_count = options.categoryDenylist.length;
  if (options.displayNamesLocale case final locale?) {
    output.display_names_locale = locale.toNativeUtf8(allocator: arena).cast();
  }
}
