/// Inputs, modes and the options and task bases every vision task shares.
library;

import 'dart:typed_data';

import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:meta/meta.dart';

import '../../models.dart' show VisionModels;

/// How a task is fed, chosen when it is created.
enum RunningMode {
  /// Independent still images.
  image,

  /// Frames with strictly increasing timestamps; every frame is processed.
  video,

  // TODO: Split LIVE_STREAM from VIDEO. Google's LIVE_STREAM returns at once,
  // sends results to a listener and drops frames while busy (one in flight,
  // the newest one queued), while VIDEO processes every frame. Cameras use
  // VIDEO here, and the gallery and the vision example drop frames by hand.
  // The plan, Google's behavior and the emulate-or-native decision are in
  // packages/mediapipe-task-vision/tool/LIVE_STREAM.md, and
  // `git grep -n "TODO.*LIVE_STREAM"` lists every site to revisit.
  /// Reserved for asynchronous frames and a results stream.
  ///
  /// Task creation throws [UnsupportedError] until the runtime implements
  /// live stream delivery.
  liveStream,
}

/// Channel order of 8-bit input pixels.
enum VisionPixelFormat {
  /// Red, green, blue.
  rgb(3),

  /// Red, green, blue, alpha. This is not BGRA.
  rgba(4),

  /// Blue, green, red, alpha, as Apple cameras supply it. Google's iOS SDK
  /// accepts BGRA directly; the other runtimes convert it to RGBA.
  bgra(4);

  const VisionPixelFormat(this.channels);

  /// Bytes per pixel.
  final int channels;
}

/// Whether this program runs in a browser, where images can be browser frames.
const _web = bool.fromEnvironment('dart.library.js_interop');

/// An input image. Pixel buffers are copied; the caller never owns native
/// memory and may reuse its buffer at once.
@immutable
final class VisionImage {
  /// Decodes a file with Google's image loader, EXIF orientation included.
  /// [path] is a file on native platforms and a URL, resolved against the
  /// page, in browsers.
  VisionImage.fromFile(String path)
    : path = path,
      pixels = null,
      browserFrame = null,
      width = null,
      height = null,
      format = null,
      bytesPerRow = null {
    if (path.isEmpty || path.contains('\u0000')) {
      throw ArgumentError.value(path, 'path', 'Invalid path');
    }
  }

  /// Copies RGB, RGBA or BGRA bytes, optionally with camera row padding.
  ///
  /// [bytesPerRow] defaults to the width times the channel count. The buffer
  /// must hold exactly height times bytesPerRow bytes. Padding is removed on
  /// the way to the runtime; nothing is resized, rotated or normalized here.
  VisionImage.fromPixels({
    required Uint8List pixels,
    required int width,
    required int height,
    required VisionPixelFormat format,
    int? bytesPerRow,
  }) : path = null,
       browserFrame = null,
       width = width,
       height = height,
       format = format,
       bytesPerRow = bytesPerRow ?? width * format.channels,
       pixels = Uint8List.fromList(pixels).asUnmodifiableView() {
    final rowSize = this.bytesPerRow!;
    if (width <= 0 ||
        height <= 0 ||
        width > 0x7fffffff ||
        height > 0x7fffffff ||
        rowSize < width * format.channels ||
        rowSize > 0x7fffffff ||
        height > 0x7fffffff ~/ rowSize) {
      throw ArgumentError(
        'Image dimensions must be positive and fit the C API.',
      );
    }
    final size = rowSize * height;
    if (pixels.length != size) {
      throw ArgumentError(
        'Expected $size pixel-buffer bytes, received ${pixels.length}.',
      );
    }
  }

  /// Wraps a browser `ImageBitmap` or video frame of [width] by [height]
  /// pixels. The task takes ownership and releases the frame after inference,
  /// so the caller must not reuse it.
  ///
  /// Browsers only: elsewhere it throws [RuntimeUnavailableException], since
  /// no other runtime takes browser objects. Use [VisionImage.fromPixels] or
  /// [VisionImage.fromFile] there.
  VisionImage.fromBrowserFrame(
    Object frame, {
    required int width,
    required int height,
  }) : path = null,
       pixels = null,
       browserFrame = frame,
       width = width,
       height = height,
       format = null,
       bytesPerRow = null {
    if (!_web) {
      throw const RuntimeUnavailableException(
        'Browser frames exist in browsers only.',
        fix: 'Use VisionImage.fromPixels or VisionImage.fromFile here.',
      );
    }
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Frame dimensions must be positive.');
    }
  }

  /// The file (native) or URL (browser), or null for other inputs.
  final String? path;

  /// Owned, read-only pixels, or null for other inputs.
  final Uint8List? pixels;

  /// The browser frame, or null for other inputs.
  final Object? browserFrame;

  /// Pixel width, which the runtime reads for file input.
  final int? width;

  /// Pixel height, which the runtime reads for file input.
  final int? height;

  /// Channel order of [pixels]; null for other inputs.
  final VisionPixelFormat? format;

  /// Bytes between the starts of adjacent pixel rows, padding included; null
  /// for other inputs.
  final int? bytesPerRow;
}

/// A region of an image in normalized coordinates, for the tasks that accept
/// one (Image Classifier and Image Embedder).
@immutable
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

/// What every vision task's options add to [TaskOptions]: the running mode.
abstract base class VisionTaskOptions extends TaskOptions {
  /// Validates the shared values; subclasses add their task's settings.
  VisionTaskOptions({
    super.model,
    super.modelPath,
    super.modelBytes,
    super.delegate,
    this.runningMode = RunningMode.image,
  }) : super(family: 'mediapipe_vision', registry: VisionModels.byName);

  /// Still images or timestamped frames.
  final RunningMode runningMode;
}

/// What every vision task has, so an app can hold any task through one type.
abstract interface class VisionTask {
  /// The processor the task runs on, fixed at creation.
  Delegate get delegate;

  /// The mode the task was created in.
  RunningMode get runningMode;

  /// Finishes accepted work and releases Google's task. Repeated calls return
  /// the same completion; any other call afterwards throws [StateError].
  Future<void> dispose();
}

/// Requires a finite confidence in [0, 1].
void checkConfidence(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(value, name, 'Must be finite and in [0, 1]');
  }
}

/// Requires a positive count that fits a C int.
void checkCount(int value, String name) {
  if (value < 1 || value > 0x7fffffff) {
    throw ArgumentError.value(value, name, 'Must be a positive C int');
  }
}

/// Owns immutable nested lists.
List<List<T>> ownNestedLists<T>(List<List<T>> values) =>
    List.unmodifiable(values.map((v) => List<T>.unmodifiable(v)));
