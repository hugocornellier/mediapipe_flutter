"""Generate the gallery's pubspec and assets for one build target.

The build hook refuses a task it has no runtime for, so the task list cannot be
written by hand: it differs per platform, and for unpublished runtimes it also
depends on whether a maintainer source build is present. Deriving it here from
`sdk_downloads.dart` keeps the gallery buildable everywhere and keeps the tile
grid honest, because the app only ships tasks whose runtime really exists.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import urllib.request

GALLERY = Path(__file__).resolve().parents[1]
REPO = GALLERY.parent
VISION = REPO / 'packages/mediapipe-task-vision'
TEXT = REPO / 'packages/mediapipe-task-text'
AUDIO = REPO / 'packages/mediapipe-task-audio'

CAMERA_REASON = 'Show live face, hand and pose landmarks from your camera.'


def set_plist_key(path, key, value):
    """Set one top-level key in a plist, leaving nested dicts alone.

    Editing the XML by hand looks tempting until a file has nested
    dictionaries: iOS Info.plist carries a scene manifest, so appending before
    `</dict>` writes the key into every scene configuration as well as the
    root. plistlib addresses the root and nothing else.
    """
    if not path.exists():
        return False
    plist = plistlib.loads(path.read_bytes())
    if plist.get(key) == value:
        return False
    plist[key] = value
    path.write_bytes(plistlib.dumps(plist))
    return True

# The hook hard-codes this set for Android; see hook/build.dart _bundleAndroid.
ANDROID_TASKS = {'face_detector', 'face_landmarker'}

# Tasks the mediapipe_flutter_vision_android plugin runs through Google's
# official SDK; see hook/build.dart officialAndroidTasks.
OFFICIAL_ANDROID_TASKS = {'face_detector', 'face_landmarker', 'gesture_recognizer',
                          'hand_landmarker', 'holistic_landmarker', 'image_classifier',
                          'image_embedder', 'image_segmenter', 'interactive_segmenter',
                          'object_detector', 'pose_landmarker'}

# Tasks validated on Google's official macOS runtime; see the vision package's
# sdk_downloads.dart officialMacosLandmarkRuntime.
OFFICIAL_MACOS_TASKS = {'face_landmarker', 'gesture_recognizer', 'hand_landmarker',
                        'holistic_landmarker', 'image_classifier', 'image_embedder',
                        'image_segmenter', 'interactive_segmenter_legacy',
                        'object_detector', 'pose_landmarker'}

# Tasks our adapter serves over Google's official iOS SDK; see
# lib/src/native_assets/ios_sdk.dart officialIosTasks.
OFFICIAL_IOS_TASKS = {'face_detector', 'face_landmarker', 'gesture_recognizer',
                      'hand_landmarker', 'holistic_landmarker', 'image_classifier',
                      'image_embedder', 'image_segmenter', 'interactive_segmenter',
                      'interactive_segmenter_legacy', 'object_detector',
                      'pose_landmarker'}

# Tasks the browser adapter runs on Google's official web runtime.
WEB_TASKS = {'face_detector', 'face_landmarker', 'gesture_recognizer',
             'hand_landmarker', 'holistic_landmarker', 'image_classifier',
             'image_embedder', 'image_segmenter', 'interactive_segmenter',
             'interactive_segmenter_legacy', 'object_detector',
             'pose_landmarker', 'audio_classifier', 'language_detector',
             'text_classifier', 'text_embedder'}

# The stateful MagicTouch runtime lives in mediapipe-core's tasks runtime on
# macOS arm64 (Linux's vision wheel exports it itself), and the hook wants it
# opted into through a separate user define.
SHARED_RUNTIME_TASK = 'interactive_segmenter'
SHARED_RUNTIME_TARGETS = {'macos/arm64'}
# Core's tasks runtime serves the text and audio tasks on these targets. On
# Linux and Windows it is Google's wheel library, which the vision tasks then
# share instead of bundling a second copy; on iOS it is the vision package's
# official SDK adapter.
TEXT_AUDIO_TARGETS = {'macos/arm64', 'linux/x64', 'windows/x64', 'ios/arm64',
                      'ios-simulator/arm64'}

# The text package's three classic tasks, on the same shared runtime, with the
# models its example downloads and verifies (make models_text). They are not
# vision tasks, so they stay out of the vision hook's task list.
TEXT_TASKS = {'language_detector': 'language_detector.tflite',
              'text_classifier': 'bert_classifier.tflite',
              'text_embedder': 'universal_sentence_encoder.tflite'}

# The audio package's Audio Classifier, on the same shared runtime, with the
# model its tool downloads (make models_audio) and Google's sample clips.
AUDIO_TASKS = {'audio_classifier': 'yamnet.tflite'}
AUDIO_SAMPLES = ['speech_16000_hz_mono.wav', 'speech_48000_hz_mono.wav',
                 'two_heads_16000_hz_mono.wav']
# Tasks outside the vision package, which its hook must not be asked for.
NON_VISION_TASKS = {*TEXT_TASKS, *AUDIO_TASKS}

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


def _pinned_model(task):
    """The URL and SHA-256 the text or audio package pins for [task]'s model."""
    if task in AUDIO_TASKS:
        source = (AUDIO / 'lib/models.dart').read_text()
        url = re.search(r"const yamnetUrl =(.*?);", source, re.S).group(1)
        sha = re.search(r"const yamnetSha256 =\s*'([0-9a-f]{64})'", source).group(1)
    else:
        constant = {'language_detector': 'languageDetectorModel',
                    'text_classifier': 'bertClassifierModel',
                    'text_embedder': 'universalSentenceEncoderModel'}[task]
        source = (TEXT / 'lib/models.dart').read_text()
        row = re.search(r'const DownloadAsset ' + constant + r' = \((.*?)\);', source, re.S).group(1)
        url = re.search(r'url:(.*?),\s*sha256', row, re.S).group(1)
        sha = re.search(r"sha256:\s*'([0-9a-f]{64})'", row).group(1)
    return ''.join(re.findall(r"'([^']*)'", url)), sha


def _download_model(task, destination):
    """Fetches a missing text or audio model from its pinned URL.

    The packages' own download tools run their build hooks, which refuse the
    shared runtime on hosts without one, such as the Linux web runner.
    """
    url, sha = _pinned_model(task)
    destination.parent.mkdir(parents=True, exist_ok=True)
    data = urllib.request.urlopen(url, timeout=120).read()
    if hashlib.sha256(data).hexdigest() != sha:
        raise RuntimeError(f'{url} does not match its pinned SHA-256')
    destination.write_bytes(data)


def available_tasks(target):
    """Tasks whose runtime this target can actually obtain."""
    if target == 'web':
        return set(WEB_TASKS)
    source = (VISION / 'sdk_downloads.dart').read_text()
    if target in ('ios/arm64', 'ios-simulator/arm64'):
        # Google's public SDK supplies these tasks without a maintainer build;
        # its adapter serves text and audio through core's runtime too.
        return set(OFFICIAL_IOS_TASKS) | NON_VISION_TASKS
    if target.startswith('android'):
        # Text and audio run through their packages' Android SDK plugins.
        return ANDROID_TASKS | OFFICIAL_ANDROID_TASKS | NON_VISION_TASKS
    if target in ('linux/x64', 'windows/x64'):
        for block in _blocks(source, 'const visionWheelReleases'):
            if re.search(r"target: '" + re.escape(target) + r"'", block):
                return _tasks_of(block) | NON_VISION_TASKS
        return set()
    tasks = set()
    if target in SHARED_RUNTIME_TARGETS:
        tasks.add(SHARED_RUNTIME_TASK)
        tasks |= set(TEXT_TASKS) | set(AUDIO_TASKS)
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
    if target == 'web':
        subprocess.run([sys.executable, '-B', str(REPO / 'packages/mediapipe-task-vision-web/tool/prepare_model.py')], check=True)
    assets = GALLERY / 'assets/models'
    if assets.exists():
        shutil.rmtree(assets)
    assets.mkdir(parents=True)
    bundled = {}
    missing = []
    for task in sorted(selected):
        if task in TEXT_TASKS:
            name = TEXT_TASKS[task]
            source = TEXT / 'example/assets' / name
        elif task in AUDIO_TASKS:
            name = AUDIO_TASKS[task]
            source = AUDIO / 'models' / name
        elif task in MODELS:
            _, name = MODELS[task]
            source = VISION / 'models' / name
        else:
            continue
        if not source.exists() and task in NON_VISION_TASKS:
            _download_model(task, source)
        if not source.exists():
            missing.append(f'{task} -> {name}')
            continue
        shutil.copyfile(source, assets / name)
        bundled[task] = name
    if (target == 'macos/arm64'
            and OFFICIAL_MACOS_TASKS & bundled.keys()):
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
    audio_samples = AUDIO_SAMPLES if 'audio_classifier' in bundled else []
    for name in audio_samples:
        shutil.copyfile(AUDIO / 'test/fixtures' / name, samples / name)

    official_landmarks = (target == 'macos/arm64'
                          and OFFICIAL_MACOS_TASKS & bundled.keys())
    official_android = (target.startswith('android') and bundled
                        and set(bundled) - NON_VISION_TASKS <= OFFICIAL_ANDROID_TASKS)
    if target == 'web':
        for runtime in ('vision', 'text', 'audio'):
            subprocess.run([sys.executable, '-B', str(REPO / f'packages/mediapipe-task-{runtime}-web/tool/prepare_runtime.py')], check=True)
    manifest = {
        'target': target,
        'tasks': sorted(bundled),
        'models': bundled,
        'samples': sorted([*SAMPLES.values(), *audio_samples]),
        'official_macos_landmark_tasks': sorted(
            OFFICIAL_MACOS_TASKS & bundled.keys()) if official_landmarks else [],
        'official_ios_sdk': '1.0.1' if target.startswith('ios') else None,
        'official_android_sdk': '1.0.0' if official_android else None,
        'official_web_sdk': '1.0.1' if target == 'web' else None,
    }
    (GALLERY / 'assets/manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')

    entries = '\n'.join(
        [f'    - assets/models/{name}' for name in sorted(bundled.values())]
        + [f'    - assets/samples/{name}'
           for name in sorted([*SAMPLES.values(), *audio_samples])])
    # camera_desktop supplies native desktop preview and raw image streaming;
    # camera itself supplies the mobile implementations.
    camera = ('  camera: ^0.12.1\n  camera_desktop: ^1.2.2'
              if target in ('macos/arm64', 'linux/x64', 'windows/x64')
              else '  camera: ^0.12.1' if target == 'web' or target.startswith(('ios', 'android')) else '')
    android_plugin = ('''  mediapipe_flutter_vision_android:
    path: ../packages/mediapipe-task-vision-android
''' if official_android else '')
    if target.startswith('android'):
        if set(TEXT_TASKS) & bundled.keys():
            android_plugin += '''  mediapipe_flutter_text_android:
    path: ../packages/mediapipe-task-text-android
'''
        if set(AUDIO_TASKS) & bundled.keys():
            android_plugin += '''  mediapipe_flutter_audio_android:
    path: ../packages/mediapipe-task-audio-android
'''
    web_plugin = ('''  mediapipe_flutter_vision_web:
    path: ../packages/mediapipe-task-vision-web
  mediapipe_flutter_text_web:
    path: ../packages/mediapipe-task-text-web
  mediapipe_flutter_audio_web:
    path: ../packages/mediapipe-task-audio-web
''' if target == 'web' else '')
    # Core's shared runtime is opted into explicitly, on the core package: the
    # vision hook refuses the stateful MagicTouch task on macOS without it, and
    # the text and audio tasks need it wherever they run natively.
    core = ('    mediapipe_flutter_core:\n      tasks_runtime: true\n'
            if (({SHARED_RUNTIME_TASK} & bundled.keys()
                 and target in SHARED_RUNTIME_TARGETS)
                or (NON_VISION_TASKS & bundled.keys()
                    and target in TEXT_AUDIO_TARGETS))
            else '')
    # On the web, Google's JavaScript runs the stateful task. Host-side builds
    # such as `flutter test --platform chrome` still run the native hook, which
    # must not be asked for a runtime this app never loads.
    native_tasks = sorted(set(bundled) - NON_VISION_TASKS
                          - ({SHARED_RUNTIME_TASK} if target == 'web' else set()))
    official_landmarks_define = (
        '      official_macos_landmark_tasks: true\n'
        if official_landmarks else '')
    official_ios_define = ('      official_ios_sdk: true\n'
                           if target.startswith('ios') else '')
    official_android_define = ('      official_android_sdk: true\n'
                               if official_android else '')
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
  mediapipe_flutter_core:
    path: ../packages/mediapipe-core
  mediapipe_flutter_text:
    path: ../packages/mediapipe-task-text
  mediapipe_flutter_audio:
    path: ../packages/mediapipe-task-audio
  web: ^1.1.1
  # Verifies downloaded models; picks a model file to upload; records the
  # Audio Classifier demo's microphone.
  crypto: ^3.0.6
  file_selector: ^1.0.3
  record: ^7.1.1
{android_plugin}{web_plugin}{camera}

dev_dependencies:
  camera_platform_interface: ^2.13.1
  flutter_lints: ^6.0.0
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter

hooks:
  user_defines:
{core}    mediapipe_flutter_vision:
{official_landmarks_define}{official_ios_define}{official_android_define}      tasks: [{', '.join(native_tasks)}]

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
            set_plist_key(GALLERY / f'macos/Runner/{name}.entitlements',
                          'com.apple.security.device.camera', True)
        set_plist_key(GALLERY / 'macos/Runner/Info.plist',
                      'NSCameraUsageDescription', CAMERA_REASON)
    if target.startswith('ios'):
        # A live tile needs the camera, and iOS kills an app that asks without
        # a usage string. The device runtime also needs a deployment target it
        # supports; flutter create defaults below it.
        set_plist_key(GALLERY / 'ios/Runner/Info.plist',
                      'NSCameraUsageDescription', CAMERA_REASON)
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
    parser.add_argument('--tasks', help='Comma-separated subset of available tasks')
    args = parser.parse_args()
    target = args.target or host_target()
    if target is None:
        raise SystemExit('No MediaPipe runtime target matches this host.')
    selected = available_tasks(target)
    if target.startswith('android') and not args.tasks:
        # The public SDKs need no maintainer C++ build; vision supplies CPU/GPU.
        selected = set(OFFICIAL_ANDROID_TASKS) | NON_VISION_TASKS
    if args.tasks:
        requested = set(args.tasks.split(','))
        if not requested <= selected:
            raise SystemExit(f'Unavailable tasks for {target}: {requested - selected}')
        selected = requested
    if (target.startswith('android') and selected - ANDROID_TASKS - NON_VISION_TASKS
            and not selected - NON_VISION_TASKS <= OFFICIAL_ANDROID_TASKS):
        # One app uses either the official plugin or the source-built runtime.
        raise SystemExit('On Android, tasks beyond the source-built face tasks '
                         'run only through the official SDK plugin, which serves '
                         f'{sorted(OFFICIAL_ANDROID_TASKS)} only.')
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
