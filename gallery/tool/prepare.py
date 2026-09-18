"""Generate the gallery's pubspec and assets for one build target.

The build hook refuses a task it has no runtime for, so the task list cannot be
written by hand: it differs per platform, and for unpublished runtimes it also
depends on whether a maintainer source build is present. Deriving it here from
`sdk_downloads.dart` keeps the gallery buildable everywhere and keeps the tile
grid honest, because the app only ships tasks whose runtime really exists.
"""
import argparse
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys

GALLERY = Path(__file__).resolve().parents[1]
REPO = GALLERY.parent
VISION = REPO / 'packages/mediapipe-task-vision'

# The hook hard-codes this set for Android; see hook/build.dart _bundleAndroid.
ANDROID_TASKS = {'face_detector', 'face_landmarker'}

# The stateful MagicTouch runtime lives in mediapipe-core's tasks runtime,
# which is published for macOS arm64 only, and the hook wants it opted into
# through a separate user define.
SHARED_RUNTIME_TASK = 'interactive_segmenter'
SHARED_RUNTIME_TARGETS = {'macos/arm64'}

# Sample inputs, reused from the test fixtures so the gallery ships nothing new
# and inherits their recorded provenance and licence.
SAMPLES = {
    'face_detection/landmark-ex1.jpg': 'portrait.jpg',
    'face_detection/group-shot-bounding-box-ex1.jpeg': 'group.jpeg',
    'landmark_tasks/right_hands.jpg': 'hands.jpg',
    'landmark_tasks/pose.jpg': 'pose.jpg',
    'landmark_tasks/thumb_up.jpg': 'thumb_up.jpg',
    'interactive_segmentation/cats_and_dogs.jpg': 'animals.jpg',
}

MODELS = {
    'face_detector': ('blazeFaceShortRange', 'blaze_face_short_range.tflite'),
    'face_landmarker': ('faceLandmarker', 'face_landmarker.task'),
    'object_detector': ('efficientDetLite0', 'efficientdet_lite0.tflite'),
    'image_classifier': ('efficientNetLite0', 'efficientnet_lite0.tflite'),
    'image_embedder': ('mobileNetV3Small', 'mobilenet_v3_small.tflite'),
    'hand_landmarker': ('handLandmarker', 'hand_landmarker.task'),
    'gesture_recognizer': ('gestureRecognizer', 'gesture_recognizer.task'),
    'pose_landmarker': ('poseLandmarkerLite', 'pose_landmarker_lite.task'),
    'holistic_landmarker': ('holisticLandmarker', 'holistic_landmarker.task'),
    'image_segmenter': ('deepLabV3', 'deeplab_v3.tflite'),
    'interactive_segmenter_legacy': ('magicTouch', 'magic_touch.tflite'),
    'interactive_segmenter': ('interactiveSegmentation',
                              'interactive_segmentation.task'),
}


def host_target():
    system, machine = platform.system(), platform.machine().lower()
    if system == 'Darwin' and machine == 'arm64':
        return 'macos/arm64'
    if machine in ('amd64', 'x86_64'):
        return {'Linux': 'linux/x64', 'Windows': 'windows/x64'}.get(system)
    return None


def _blocks(source, marker):
    """Yields each `VisionRuntimeRelease(...)` style block after `marker`."""
    start = source.index(marker)
    depth, block, blocks = 0, [], []
    for char in source[start:]:
        if char == '(':
            depth += 1
        if depth:
            block.append(char)
        if char == ')':
            depth -= 1
            if depth == 0:
                blocks.append(''.join(block))
                block = []
            elif depth < 0:
                break
    return blocks


def _tasks_of(block):
    match = re.search(r'tasks: \{(.*?)\}', block, re.S)
    return {t.strip().strip("'") for t in match.group(1).split(',') if t.strip()}


def available_tasks(target):
    """Tasks whose runtime this target can actually obtain."""
    source = (VISION / 'sdk_downloads.dart').read_text()
    if target in ('ios/arm64', 'ios-simulator/arm64'):
        # Google's public SDK supplies these tasks without a maintainer build.
        return {'face_detector', 'face_landmarker'}
    if target.startswith('android'):
        return set(ANDROID_TASKS)
    if target in ('linux/x64', 'windows/x64'):
        for block in _blocks(source, 'const visionWheelReleases'):
            if re.search(r"target: '" + re.escape(target) + r"'", block):
                return _tasks_of(block)
        return set()
    tasks = set()
    if target in SHARED_RUNTIME_TARGETS:
        tasks.add(SHARED_RUNTIME_TASK)
    for block in _blocks(source, 'const visionRuntimeReleases'):
        if not re.search(r"target: '" + re.escape(target) + r"'", block):
            continue
        published = not re.search(r'archive: null', block)
        if not published:
            # Unpublished rows need a maintainer build sitting in the package.
            local = re.search(r"localBuildDirectory: '([^']*)'", block)
            library = re.search(r"libraryName: '([^']*)'", block)
            if not (local and library
                    and (VISION / local.group(1) / library.group(1)).exists()):
                continue
        tasks |= _tasks_of(block)
    return tasks


def prepare(target, selected):
    assets = GALLERY / 'assets/models'
    if assets.exists():
        shutil.rmtree(assets)
    assets.mkdir(parents=True)
    bundled = {}
    missing = []
    for task in sorted(selected):
        if task not in MODELS:
            continue
        _, name = MODELS[task]
        source = VISION / 'models' / name
        if not source.exists():
            missing.append(f'{task} -> {name}')
            continue
        shutil.copyfile(source, assets / name)
        bundled[task] = name
    if (target == 'macos/arm64'
            and {'face_landmarker', 'hand_landmarker',
                 'pose_landmarker'} & bundled.keys()):
        subprocess.run([
            sys.executable, '-B',
            str(VISION / 'tool/prepare_official_macos_landmark_runtime.py'),
        ], cwd=VISION, check=True)
    samples = GALLERY / 'assets/samples'
    if samples.exists():
        shutil.rmtree(samples)
    samples.mkdir(parents=True)
    for source, name in SAMPLES.items():
        shutil.copyfile(VISION / 'test/fixtures' / source, samples / name)

    official_landmarks = (target == 'macos/arm64'
                          and {'face_landmarker', 'hand_landmarker',
                               'pose_landmarker'} & bundled.keys())
    manifest = {
        'target': target,
        'tasks': sorted(bundled),
        'models': bundled,
        'samples': sorted(SAMPLES.values()),
        'official_macos_landmark_tasks': sorted(
            {'face_landmarker', 'hand_landmarker', 'pose_landmarker'}
            & bundled.keys()) if official_landmarks else [],
        'official_ios_sdk': '1.0.1' if target.startswith('ios') else None,
    }
    (GALLERY / 'assets/manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')

    entries = '\n'.join(
        [f'    - assets/models/{name}' for name in sorted(bundled.values())]
        + [f'    - assets/samples/{name}' for name in sorted(SAMPLES.values())])
    # Only pulled in where the live tile can appear, so other targets do not
    # carry a camera plugin they never register. See catalog.dart.
    camera = ('  camera: ^0.12.1\n  camera_desktop: ^1.2.1'
              if target == 'macos/arm64'
              else '  camera: ^0.12.1' if target.startswith('ios') else '')
    # The hook refuses the stateful MagicTouch task unless its shared runtime is
    # opted into explicitly, on the core package rather than the vision one.
    core = ('    mediapipe_flutter_core:\n      tasks_runtime: true\n'
            if SHARED_RUNTIME_TASK in bundled else '')
    official_landmarks_define = (
        '      official_macos_landmark_tasks: true\n'
        if official_landmarks else '')
    official_ios_define = ('      official_ios_sdk: true\n'
                           if target.startswith('ios') else '')
    (GALLERY / 'pubspec.yaml').write_text(f'''# Generated by tool/prepare.py for {target}. Do not edit by hand:
# the task list is per-target and the build hook rejects unavailable tasks.
name: mediapipe_gallery
description: A portal to every MediaPipe task this repository supports.
publish_to: none
version: 0.1.0+1

environment:
  sdk: ^3.12.0

dependencies:
  flutter:
    sdk: flutter
  mediapipe_flutter_vision:
    path: ../packages/mediapipe-task-vision
{camera}

dev_dependencies:
  crypto: ^3.0.6
  flutter_lints: ^6.0.0
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter

hooks:
  user_defines:
{core}    mediapipe_flutter_vision:
{official_landmarks_define}{official_ios_define}      tasks: [{', '.join(sorted(bundled))}]

flutter:
  uses-material-design: true
  assets:
    - assets/manifest.json
{entries}
''')
    return manifest, missing


def pin_architecture(target):
    """Keep release builds on the one architecture the runtime ships for.

    Flutter defaults macOS release builds to a universal binary, and the hook
    refuses the x86_64 slice because no macos/x64 runtime exists.
    """
    if target == 'macos/arm64':
        config = GALLERY / 'macos/Runner/Configs/AppInfo.xcconfig'
        if config.exists():
            settings = config.read_text()
            if 'EXCLUDED_ARCHS' not in settings:
                config.write_text(
                    settings + '\nARCHS = arm64\nEXCLUDED_ARCHS = x86_64\n')
                return 'pinned macOS builds to arm64'
    if target == 'macos/arm64':
        # The live tile needs camera access; a sandboxed macOS app is denied it
        # without the entitlement, and macOS kills it without the usage string.
        for name in ('DebugProfile', 'Release'):
            entitlements = GALLERY / f'macos/Runner/{name}.entitlements'
            if entitlements.exists():
                text = entitlements.read_text()
                if 'com.apple.security.device.camera' not in text:
                    entitlements.write_text(text.replace(
                        '</dict>',
                        '\t<key>com.apple.security.device.camera</key>\n'
                        '\t<true/>\n</dict>'))
        info = GALLERY / 'macos/Runner/Info.plist'
        if info.exists():
            text = info.read_text()
            if 'NSCameraUsageDescription' not in text:
                info.write_text(text.replace(
                    '</dict>',
                    '\t<key>NSCameraUsageDescription</key>\n'
                    '\t<string>Show a live face mesh from your camera on this '
                    'Mac.</string>\n</dict>'))
    if target.startswith('ios'):
        project = GALLERY / 'ios/Runner.xcodeproj/project.pbxproj'
        if project.exists():
            settings = project.read_text()
            updated = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = (?:13|14)\.0;',
                             'IPHONEOS_DEPLOYMENT_TARGET = 15.0;', settings)
            if updated != settings:
                project.write_text(updated)
    if target == 'ios-simulator/arm64':
        project = GALLERY / 'ios/Runner.xcodeproj/project.pbxproj'
        if project.exists():
            settings = project.read_text()
            if 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' not in settings:
                project.write_text(settings.replace(
                    'buildSettings = {',
                    'buildSettings = {\n\t\t\t\t'
                    '"EXCLUDED_ARCHS[sdk=iphonesimulator*]" = x86_64;'))
                return 'excluded the x86_64 simulator slice'
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', help='Defaults to this host')
    args = parser.parse_args()
    target = args.target or host_target()
    if target is None:
        raise SystemExit('No MediaPipe runtime target matches this host.')
    selected = available_tasks(target)
    if not selected:
        raise SystemExit(f'No vision runtime is available for {target}.')
    manifest, missing = prepare(target, selected)
    pinned = pin_architecture(target)
    if pinned:
        print(f'  {pinned}')
    print(f'{target}: {len(manifest["tasks"])} task(s) bundled')
    for task in manifest['tasks']:
        print(f'  + {task}')
    for entry in missing:
        print(f'  ! model not downloaded, task skipped: {entry}')


if __name__ == '__main__':
    main()
