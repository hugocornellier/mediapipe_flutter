import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:mediapipe_flutter_core/src/native_assets/tasks_runtime.dart';
import 'package:mediapipe_flutter_vision/src/native_assets/wheel_library.dart';

/// Every task name accepted by `hooks.user_defines.mediapipe_flutter_vision.tasks`.
///
/// Tasks other than MagicTouch come from the pinned v1.0.0 source build;
/// MagicTouch is served by core's shared official 1.0.1 runtime.
const visionTasks = {
  'face_detector',
  'face_landmarker',
  'gesture_recognizer',
  'hand_landmarker',
  'holistic_landmarker',
  'image_classifier',
  'image_embedder',
  'image_segmenter',
  'interactive_segmenter',
  'interactive_segmenter_legacy',
  'object_detector',
  'pose_landmarker',
};

/// The one task served by core's runtime instead of a vision release.
const sharedRuntimeTask = 'interactive_segmenter';

/// A pinned, immutable source-built runtime covering [tasks] on one target.
///
/// A rebuild gets a new release tag and new digests. Never replace an archive
/// in place or resolve a floating "latest" URL from the build hook.
final class VisionRuntimeRelease {
  /// Describe a published release.
  const VisionRuntimeRelease({
    required this.target,
    required this.release,
    required this.tasks,
    required this.archive,
    required this.libraryName,
    required this.librarySha256,
    required this.assetName,
    required this.localBuildDirectory,
  });

  /// Build target such as `macos/arm64`; see `buildTarget`.
  final String target;

  /// Release tag in the public native runtime repository.
  final String release;

  /// Tasks whose C API this library exports.
  final Set<String> tasks;

  /// The archive holding the library, notices and `manifest.json`, or null
  /// while the release is built but not yet published.
  ///
  /// A null archive is not a placeholder for a future URL: the hook refuses to
  /// invent one and serves the release only from [localBuildDirectory], so a
  /// maintainer can develop against a source build without anyone pinning an
  /// address that does not answer yet.
  final DownloadAsset? archive;

  /// Bundle filename of the library inside the archive.
  final String libraryName;

  /// SHA-256 of the library, pinned independently of the downloaded manifest.
  final String librarySha256;

  /// Code asset name the bindings reference, without the package prefix.
  final String assetName;

  /// Package-relative directory where `tool/build_native.py` writes the same
  /// library, so maintainers can test a source build before publishing it.
  final String localBuildDirectory;
}

/// Published vision runtimes. Add a row per (release, target); the hook
/// downloads each release that covers a selected task exactly once.
const visionRuntimeReleases = <VisionRuntimeRelease>[
  VisionRuntimeRelease(
    target: 'macos/arm64',
    release: 'face-detector-v1.0.0-2',
    tasks: {'face_detector'},
    archive: (
      url:
          'https://github.com/hugocornellier/mediapipe_flutter_native/releases/'
          'download/face-detector-v1.0.0-2/'
          'mediapipe-face-detector-1.0.0-macos-arm64.tar.gz',
      sha256:
          'bbebd7ef2cfd95df89a757f6d8620c1fb5a12a2d55c2858082fecacf979ab87c',
    ),
    libraryName: 'libface_detector.dylib',
    librarySha256:
        'c57d0698684e0abcb6a2cfb5a7d38855a7044a43c9714add50f92f36525c9497',
    assetName: 'face_detector.dylib',
    localBuildDirectory: 'build/native/',
  ),
  VisionRuntimeRelease(
    target: 'macos/arm64',
    release: 'face-landmarker-v1.0.0-2',
    tasks: {'face_landmarker'},
    archive: (
      url:
          'https://github.com/hugocornellier/mediapipe_flutter_native/releases/'
          'download/face-landmarker-v1.0.0-2/'
          'mediapipe-face-landmarker-1.0.0-macos-arm64.tar.gz',
      sha256:
          '0c72b6af47508a50a67a137bc5313c990d91da8a819041431bf6408aa5656f83',
    ),
    libraryName: 'libface_landmarker.dylib',
    librarySha256:
        '825cdbb58d763d87a0e35b8c38406ac738841ac7bbe1af6888de5b7e1074f4f9',
    assetName: 'face_landmarker.dylib',
    localBuildDirectory: 'build/native/face_landmarker/',
  ),
  // The combined source build from `//mediapipe/tasks/c:libmediapipe`. It also
  // exports the two face tasks, but they are deliberately left to the published
  // rows above so existing consumers keep downloading exactly what they do
  // today. Selecting a face task alongside one of these bundles both libraries;
  // that ends when this release is published and supersedes them.
  VisionRuntimeRelease(
    target: 'macos/arm64',
    release: 'vision-v1.0.0-1',
    tasks: {
      'gesture_recognizer',
      'hand_landmarker',
      'holistic_landmarker',
      'image_classifier',
      'image_embedder',
      'image_segmenter',
      'interactive_segmenter_legacy',
      'object_detector',
      'pose_landmarker',
    },
    archive: null,
    libraryName: 'libmediapipe.dylib',
    librarySha256:
        'dbc5ea41d10c334e2f7adc9a746f109334d0826abbd9cedd5d03360c8b4f6238',
    assetName: 'vision.dylib',
    localBuildDirectory: 'build/native/tasks/',
  ),
];

/// Targets whose vision runtimes exist only as maintainer builds made by
/// `tool/build_ios_simulator.py`; nothing is published for them yet.
const localOnlyVisionTargets = {'ios-simulator/arm64'};

/// Official desktop CPU runtimes. Coverage grows only after inference tests pass.
const visionWheelReleases = <String, VisionWheelRelease>{
  'linux/x64': VisionWheelRelease(
    target: 'linux/x64',
    wheel: (
      url:
          'https://files.pythonhosted.org/packages/d3/1d/'
          'bc666b2edee87cc06421b040df0282607339091954ab9d4906a65a45be10/'
          'mediapipe-1.0.0-py3-none-manylinux_2_28_x86_64.whl',
      sha256:
          '07a449446bf888a8a2787dbf6fc1a33da4c47977313deec64d13c35bff41f6d2',
    ),
    libraryName: 'libmediapipe.so',
    librarySha256:
        '35ef4187d381addb1309f0f9dedd32613127fa98d1ad1f5ddeea57595cdbcaf0',
    notices: _wheelNotices,
    tasks: {'face_detector', 'face_landmarker'},
  ),
  'windows/x64': VisionWheelRelease(
    target: 'windows/x64',
    wheel: (
      url:
          'https://files.pythonhosted.org/packages/68/53/'
          'ffb67e668f23130aff197ec49be912be910c128b60658000d8bf263207c9/'
          'mediapipe-1.0.0-py3-none-win_amd64.whl',
      sha256:
          'da57e6719bbab05007272c91d6ca2e0e2e370709491cbe344a372f87e25cf604',
    ),
    libraryName: 'libmediapipe.dll',
    librarySha256:
        'a8970c645c8c87c25ec9965cb5c898e803c6c42f7192b7de9a0541c62ae48cef',
    notices: _wheelNotices,
    tasks: {'face_detector', 'face_landmarker'},
  ),
};

const _wheelNotices = {
  'LICENSE': '8707eef0533987efc5b155d64761eeb6e20793f50b9bd1a68dad1cf4719d0ed8',
  'NOTICE': 'd3b4a80a24a01fd445d4b70a610fd836ec3547c3a62eb835a1041956c38d9f56',
};

/// Kept for callers that pin the face detector archive directly.
DownloadAsset get faceDetectorArchive => visionRuntimeReleases[0].archive!;

/// Kept for callers that pin the face detector library digest directly.
String get faceDetectorLibrarySha256 => visionRuntimeReleases[0].librarySha256;

/// Kept for callers that pin the face landmarker archive directly.
DownloadAsset get faceLandmarkerArchive => visionRuntimeReleases[1].archive!;

/// Kept for callers that pin the face landmarker library digest directly.
String get faceLandmarkerLibrarySha256 =>
    visionRuntimeReleases[1].librarySha256;

// Explicit opt-in only. Native bytes originate from Google's 1.0.1 wheel.
/// The shared runtime archive MagicTouch is served from, for macOS arm64.
DownloadAsset get interactiveSegmenterArchive =>
    tasksRuntimeReleases['macos/arm64']!.archive;
