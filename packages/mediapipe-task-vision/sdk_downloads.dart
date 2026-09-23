import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:mediapipe_flutter_core/src/native_assets/tasks_runtime.dart';
import 'package:mediapipe_flutter_vision/src/native_assets/vision_library.dart';
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

/// A pinned, immutable runtime covering [tasks] on one target.
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
    this.officialWheel,
  });

  /// Build target such as `macos/arm64`; see `buildTarget`.
  final String target;

  /// Release tag in the public native runtime repository.
  final String release;

  /// Task bindings served by this release. Additional exports do not imply
  /// supported inference; the capability table records validation status.
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
  ///
  /// For a release with [officialWheel] set, the library is re-signed locally
  /// and this is the digest of its unsigned image (`unsignedMachOSha256`),
  /// which does not change with the Xcode that signs it. Other releases pin
  /// the whole file.
  final String librarySha256;

  /// Primary code asset name, without the package prefix. Combined runtimes
  /// are also bundled under the other selected tasks' binding asset names.
  final String assetName;

  /// Package-relative directory where `tool/build_native.py` writes the same
  /// library, so maintainers can test a source build before publishing it.
  final String localBuildDirectory;

  /// Exact official-wheel provenance, when this is not a source build.
  final OfficialWheelProvenance? officialWheel;
}

/// Google's official 1.0.0 landmark runtime used only by explicit opt-in.
///
/// It stays separate from [visionRuntimeReleases], so package consumers keep
/// using the existing source/published runtimes unless they explicitly select
/// it. Only the tasks in [VisionRuntimeRelease.tasks] have earned a macOS
/// validation claim, even though the monolith exports every task API.
const officialMacosLandmarkRuntime = VisionRuntimeRelease(
  target: 'macos/arm64',
  release: 'official-landmarks-v1.0.0',
  tasks: {'face_landmarker', 'hand_landmarker', 'pose_landmarker'},
  archive: null,
  libraryName: 'libmediapipe.dylib',
  // Unsigned-image digest; tool/prepare_official_macos_landmark_runtime.py
  // pins the same value and records the signed digest in the manifest.
  librarySha256:
      'b4c9e10a77fabea6ecbd88f93686ee9414c01762531eb3d487240958b2327fdc',
  assetName: 'official_landmarks.dylib',
  localBuildDirectory: 'build/native/official-macos-landmarks/',
  officialWheel: OfficialWheelProvenance(
    version: '1.0.0',
    wheel: (
      url:
          'https://files.pythonhosted.org/packages/42/d7/'
          '3a5dfaa86128db110c62a4d0f0c948304817932c9dd3257313bbdf24f7d5/'
          'mediapipe-1.0.0-py3-none-macosx_11_0_arm64.whl',
      sha256:
          '7ee4783be41b2de345e1eb71e2f7e7c159a50ed5c283e60ccb8f5a6027c70a82',
    ),
    libraryPath: 'mediapipe/tasks/c/libmediapipe.dylib',
    librarySha256:
        'aa1314b6cc3eb2ce3b610808433930c016e19cdc0f62cbb3f10cc7e912b6f72f',
    minimumOS: '14.0',
    delegates: {'cpu', 'gpu'},
    notices: _wheelNotices,
  ),
);

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
        '7133bfed77463171f1af4792d3cbcb8dbbb2bb6d5a37e7aa204be856292b649e',
    assetName: 'vision.dylib',
    localBuildDirectory: 'build/native/tasks/',
  ),
  // Built with the device SDK, so it is a separate artifact from the simulator
  // slice above even though both are arm64. Face only: the landmark tasks stay
  // unvalidated here for the same reason as every other source build, and iOS
  // has no official runtime to fall back on.
  VisionRuntimeRelease(
    target: 'ios/arm64',
    release: 'vision-ios-device-v1.0.0-1',
    tasks: {'face_detector', 'face_landmarker'},
    archive: null,
    libraryName: 'libmediapipe.dylib',
    librarySha256:
        'a060f2d1f503e938e4e21432170c1b788563ed7123a6e1a71a9ab3185bae3654',
    assetName: 'face_detector.dylib',
    localBuildDirectory: 'build/native/ios/arm64/',
  ),
  VisionRuntimeRelease(
    target: 'ios-simulator/arm64',
    release: 'vision-ios-v1.0.0-1',
    tasks: {'face_detector', 'face_landmarker'},
    archive: null,
    libraryName: 'libmediapipe.dylib',
    librarySha256:
        'a4fea1f2abddb6d656b043b5471a09a64df1308475422da9800c8f880cd2aa9e',
    assetName: 'face_detector.dylib',
    localBuildDirectory: 'build/native/ios-simulator/arm64/',
  ),
];

/// Official desktop runtimes. Coverage grows only after inference tests pass.
const visionWheelReleases = <String, VisionWheelRelease>{
  'linux/x64': VisionWheelRelease(
    target: 'linux/x64',
    // 1.0.1 is the first Linux wheel built with GPU. Its C API matches 1.0.0.
    version: '1.0.1',
    wheel: (
      url:
          'https://files.pythonhosted.org/packages/2a/58/'
          'bdd5bada89d7a132375df05e962bf702c148b47043dca98d820d9395152b/'
          'mediapipe-1.0.1-py3-none-manylinux_2_28_x86_64.whl',
      sha256:
          '121522251afc3c135e4b7b0c341dd5e050ad1ec87631127484f3c389ae385044',
    ),
    libraryName: 'libmediapipe.so',
    librarySha256:
        'b72e6d61a79d1080d29a96ba95e3cfa3e43f6c433c0acc3bc9b3eb7ac0ba103a',
    notices: _linuxWheelNotices,
    tasks: {
      'face_detector',
      'face_landmarker',
      'object_detector',
      'image_classifier',
      'image_embedder',
      'hand_landmarker',
      'gesture_recognizer',
      'pose_landmarker',
      'holistic_landmarker',
      'image_segmenter',
      'interactive_segmenter_legacy',
    },
  ),
  'windows/x64': VisionWheelRelease(
    target: 'windows/x64',
    version: '1.0.0',
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
    tasks: {
      'face_detector',
      'face_landmarker',
      'object_detector',
      'image_classifier',
      'image_embedder',
      'hand_landmarker',
      'gesture_recognizer',
      'pose_landmarker',
      'holistic_landmarker',
      'image_segmenter',
      'interactive_segmenter_legacy',
    },
  ),
};

const _wheelNotices = {
  'LICENSE': '8707eef0533987efc5b155d64761eeb6e20793f50b9bd1a68dad1cf4719d0ed8',
  'NOTICE': 'd3b4a80a24a01fd445d4b70a610fd836ec3547c3a62eb835a1041956c38d9f56',
};

const _linuxWheelNotices = {
  'LICENSE': '8707eef0533987efc5b155d64761eeb6e20793f50b9bd1a68dad1cf4719d0ed8',
  'NOTICE': 'e8e3eddc5c36d7413635455933650d7423b937185180e393f9a006bee60162e7',
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
