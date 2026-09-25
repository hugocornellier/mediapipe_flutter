import 'dart:io';

import 'package:mediapipe_flutter_core/native_assets.dart';

/// A checksum-pinned native C API distributed in Google's official wheel,
/// with the vision tasks its build hook serves from it.
final class VisionWheelRelease extends OfficialWheelLibrary {
  /// Pins a target, wheel, native member, attribution files and tasks.
  const VisionWheelRelease({
    required super.target,
    required super.version,
    required super.wheel,
    required super.libraryName,
    required super.librarySha256,
    required super.notices,
    required this.tasks,
  });

  /// Tasks permitted by this release's build hook.
  final Set<String> tasks;
}

/// Extracts only the native library and pinned notices; Python is not required.
/// A cached library is reused only after checking every packaged file.
Future<File> downloadVisionWheel(VisionWheelRelease release, Directory cache) =>
    downloadOfficialWheelLibrary(release, cache);
