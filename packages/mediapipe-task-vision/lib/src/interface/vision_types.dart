import 'dart:typed_data';

/// Supported modes of the official MediaPipe task.
enum VisionRunningMode {
  /// Independent still images.
  image,

  /// Frames with monotonically increasing timestamps.
  video,
}

/// The inference backend requested for a task, fixed until it is disposed.
enum VisionDelegate {
  /// Official CPU inference. This is the default.
  cpu,

  /// Official GPU inference, using Metal for macOS and the prebuilt iOS SDK.
  /// FaceLandmarker also supports the official Android Flutter SDK adapter.
  ///
  /// Initialization errors are reported to the caller without retrying on CPU.
  /// Some stages, including face blendshapes, remain on CPU in Google's graph.
  /// Interactive Segmenter currently rejects this delegate on macOS.
  gpu,
}

/// Channel order for unsigned 8-bit input pixels.
enum VisionPixelFormat {
  /// Red, green, blue.
  rgb(3),

  /// Red, green, blue, alpha. This is not BGRA.
  rgba(4),

  /// Blue, green, red, alpha, as supplied by Apple cameras.
  /// The official iOS SDK accepts BGRA directly; other runtimes use RGBA.
  bgra(4);

  const VisionPixelFormat(this.channels);

  /// Number of bytes per pixel.
  final int channels;
}

/// Input image. Pixel buffers are copied; callers never own native pointers.
final class VisionImage {
  /// Decode a file with MediaPipe's official image loader, including EXIF.
  VisionImage.fromFile(String path)
    : path = path,
      pixels = null,
      width = null,
      height = null,
      format = null,
      bytesPerRow = null {
    if (path.isEmpty || path.contains('\u0000')) {
      throw ArgumentError.value(path, 'path', 'Invalid path');
    }
  }

  /// Copy RGB, RGBA, or BGRA bytes, optionally including camera row padding.
  ///
  /// [bytesPerRow] defaults to width times channel count. The buffer must have
  /// exactly height times bytesPerRow bytes. Row padding is removed on the
  /// inference worker; no resizing, rotation, or model normalization is done here.
  VisionImage.fromPixels({
    required Uint8List pixels,
    required int width,
    required int height,
    required VisionPixelFormat format,
    int? bytesPerRow,
  }) : path = null,
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

  /// Source file, or null for pixel input.
  final String? path;

  /// Owned, read-only pixels, or null for file input.
  final Uint8List? pixels;

  /// Pixel width, resolved by MediaPipe for file input.
  final int? width;

  /// Pixel height, resolved by MediaPipe for file input.
  final int? height;

  /// Channel order, resolved by MediaPipe for file input.
  final VisionPixelFormat? format;

  /// Bytes between the starts of adjacent pixel rows, including any padding.
  final int? bytesPerRow;
}
