import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

/// A phone picks from its photo library, as its own apps do; the web and
/// desktops open a file dialog.
Future<XFile?> pickStillImage() {
  final phone =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);
  if (phone) {
    // Without full metadata iOS shows its picker without asking for
    // photo library access.
    return ImagePicker().pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
  }
  return openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Images',
        extensions: ['jpg', 'jpeg', 'png', 'webp'],
        uniformTypeIdentifiers: ['public.image'],
      ),
    ],
  );
}

/// An encoded image decoded for a vision task: its RGBA pixels and size.
typedef StillImage = ({VisionImage input, ui.Size size});

/// Decodes [bytes] as the platform's image codec does for display, so the
/// task sees the pixels the page shows.
Future<StillImage> decodeStillImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) throw StateError('Could not decode this image.');
      return (
        input: VisionImage.fromPixels(
          pixels: rgba.buffer.asUint8List(
            rgba.offsetInBytes,
            rgba.lengthInBytes,
          ),
          width: image.width,
          height: image.height,
          format: VisionPixelFormat.rgba,
        ),
        size: ui.Size(image.width.toDouble(), image.height.toDouble()),
      );
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
