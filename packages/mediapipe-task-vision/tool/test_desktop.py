"""Validate official CPU references and isolated Flutter desktop consumers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

PACKAGE = Path(__file__).resolve().parents[1]
REPO = PACKAGE.parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, cwd, log, env=None, timeout=900):
    # Windows Flutter/Dart are batch entry points. Resolve them explicitly.
    executable = str(command[0])
    if platform.system() == 'Windows' and executable == 'dart':
        # PATHEXT lookup can spell dart.EXE in upper case. Dart 3.12's hook
        # runner then appends another .exe. Flutter's wrapper uses dart.exe.
        executable = 'dart.bat'
    command = [shutil.which(executable) or executable, *map(str, command[1:])]
    print(' '.join(command), flush=True)
    with log.open('w', encoding='utf-8') as output:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=output,
                                stderr=subprocess.STDOUT, timeout=timeout)
    print('\n'.join(log.read_text(encoding='utf-8', errors='replace').splitlines()[-25:]),
          flush=True)
    result.check_returncode()


def dart_strings(source):
    return ''.join(re.findall(r"'([^']*)'", source))


def download(url, sha, destination):
    if destination.exists() and digest(destination) == sha:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=60) as response, destination.open('wb') as output:
        shutil.copyfileobj(response, output)
    if digest(destination) != sha:
        raise RuntimeError(f'Incorrect download: {destination}')


def main():
    # Flutter emits Unicode build markers; Windows CI defaults to cp1252.
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--object-detector', action='store_true')
    parser.add_argument('--image-tasks', action='store_true')
    parser.add_argument('--landmark-tasks', action='store_true')
    parser.add_argument('--segmenter-tasks', action='store_true')
    args = parser.parse_args()
    system = platform.system()
    target = {'Linux': 'linux', 'Windows': 'windows'}.get(system)
    if target is None or platform.machine().lower() not in ('amd64', 'x86_64'):
        raise SystemExit('This validation requires Linux x64 or Windows x64.')
    build = REPO / 'build/codex-tmp'
    build.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix=f'desktop-{target}-', dir=build))
    print(f'Validation artifacts: {root}', flush=True)
    model_pins = (PACKAGE / 'lib/models.dart').read_text()
    models = [('blazeFaceShortRange', 'blaze_face_short_range.tflite'),
              ('faceLandmarker', 'face_landmarker.task')]
    if args.object_detector:
        models.append(('efficientDetLite0', 'efficientdet_lite0.tflite'))
    if args.image_tasks:
        models += [('efficientNetLite0', 'efficientnet_lite0.tflite'),
                   ('mobileNetV3Small', 'mobilenet_v3_small.tflite')]
    if args.landmark_tasks:
        models += [('handLandmarker', 'hand_landmarker.task'),
                   ('gestureRecognizer', 'gesture_recognizer.task'),
                   ('poseLandmarkerLite', 'pose_landmarker_lite.task'),
                   ('holisticLandmarker', 'holistic_landmarker.task')]
    if args.segmenter_tasks:
        models += [('deepLabV3', 'deeplab_v3.tflite'),
                   ('magicTouch', 'magic_touch.tflite')]
    for prefix, name in models:
        url = dart_strings(re.search(r'const ' + prefix + r'Url\s*=(.*?);', model_pins, re.S).group(1))
        sha = dart_strings(re.search(r'const ' + prefix + r'Sha256\s*=(.*?);', model_pins, re.S).group(1))
        download(url, sha, PACKAGE / 'models' / name)

    from cpu_reference import FACE_FILES, FACE_TASKS, generate
    references = root / 'reference'
    files = list(FACE_FILES)
    tasks = list(FACE_TASKS)
    if args.object_detector:
        tasks.append(('object_detector', 'object_detection'))
        files += ['object_detection/official_reference.json', 'object_detection/official_video_reference.json']
    if args.image_tasks:
        tasks.append(('image_tasks', 'image_tasks'))
        files.append('image_tasks/official_reference.json')
    if args.landmark_tasks:
        tasks.append(('landmark_tasks', 'landmark_tasks'))
        files.append('landmark_tasks/official_reference.json')
    if args.segmenter_tasks:
        tasks.append(('segmenter_tasks', 'segmenter_tasks'))
        files.append('segmenter_tasks/official_reference.json')
    oracle = generate(root, references, target + '/x64', tasks, files)
    library_sha = oracle['library_sha256']
    comparisons = oracle['comparisons']

    # Package copies exclude source builds, tools, caches and maintenance opt-ins.
    for name in ['mediapipe-core', 'mediapipe-task-vision']:
        source = PACKAGE.parent / name
        destination = root / 'packages' / name
        destination.mkdir(parents=True)
        shutil.copyfile(source / 'pubspec.yaml', destination / 'pubspec.yaml')
        shutil.copytree(source / 'lib', destination / 'lib')
        shutil.copytree(source / 'hook', destination / 'hook')
    vision = root / 'packages/mediapipe-task-vision'
    shutil.copyfile(PACKAGE / 'sdk_downloads.dart', vision / 'sdk_downloads.dart')
    app = root / 'app'
    run(['flutter', 'create', '--empty', '--no-pub', '--platforms=' + target,
         '--project-name', 'mediapipe_desktop_smoke', app], REPO, root / 'create.log')
    # Every selected task is bundled, asset-mapped and exercised by the app.
    selected = ['face_detector', 'face_landmarker']
    bundled = [(PACKAGE / 'models/blaze_face_short_range.tflite', 'model.tflite'),
               (PACKAGE / 'models/face_landmarker.task', 'face_landmarker.task'),
               (PACKAGE / 'test/fixtures/face_detection/portrait-301x209.rgb', 'portrait.rgb')]
    if args.object_detector:
        selected.append('object_detector')
        bundled.append((PACKAGE / 'models/efficientdet_lite0.tflite', 'object_detector.tflite'))
    if args.image_tasks:
        selected += ['image_classifier', 'image_embedder']
        bundled += [(PACKAGE / 'models/efficientnet_lite0.tflite', 'image_classifier.tflite'),
                    (PACKAGE / 'models/mobilenet_v3_small.tflite', 'image_embedder.tflite')]
    if args.landmark_tasks:
        selected += ['hand_landmarker', 'gesture_recognizer', 'pose_landmarker',
                     'holistic_landmarker']
        landmarks = PACKAGE / 'test/fixtures/landmark_tasks'
        bundled += [(PACKAGE / 'models/hand_landmarker.task', 'hand_landmarker.task'),
                    (PACKAGE / 'models/gesture_recognizer.task', 'gesture_recognizer.task'),
                    (PACKAGE / 'models/pose_landmarker_lite.task', 'pose_landmarker.task'),
                    (PACKAGE / 'models/holistic_landmarker.task', 'holistic_landmarker.task'),
                    (landmarks / 'thumb_up.rgb', 'thumb_up.rgb'),
                    (landmarks / 'pose.rgb', 'pose.rgb')]
    if args.segmenter_tasks:
        selected += ['image_segmenter', 'interactive_segmenter_legacy']
        bundled += [(PACKAGE / 'models/deeplab_v3.tflite', 'image_segmenter.tflite'),
                    (PACKAGE / 'models/magic_touch.tflite', 'magic_touch.tflite')]
    (app / 'pubspec.yaml').write_text('''name: mediapipe_desktop_smoke
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  flutter:
    sdk: flutter
  mediapipe_flutter_vision:
    path: ../packages/mediapipe-task-vision
dev_dependencies:
  archive: ^4.2.0
  crypto: ^3.0.6
  test: ^1.31.0
  integration_test:
    sdk: flutter
  flutter_test:
    sdk: flutter
hooks:
  user_defines:
    mediapipe_flutter_vision:
      prebuilt: true
      tasks: [''' + ', '.join(selected) + ''']
flutter:
  assets:
''' + ''.join(f'    - assets/{name}\n' for _, name in bundled))
    assets = app / 'assets'
    assets.mkdir()
    for source, name in bundled:
        shutil.copyfile(source, assets / name)
    shutil.copytree(PACKAGE / 'models', app / 'models',
                    ignore=shutil.ignore_patterns('*.xnnpack_cache'))
    for folder in ['fixtures/face_detection', 'fixtures/face_landmarker', 'support']:
        shutil.copytree(PACKAGE / 'test' / folder, app / 'test' / folder)
    for name in ['face_detector_test.dart', 'face_landmarker_test.dart', 'pixel_conversion_test.dart']:
        shutil.copyfile(PACKAGE / 'test' / name, app / 'test' / name)
    if args.object_detector:
        shutil.copytree(PACKAGE / 'test/fixtures/object_detection', app / 'test/fixtures/object_detection')
        shutil.copyfile(PACKAGE / 'test/object_detector_test.dart', app / 'test/object_detector_test.dart')
        shutil.copyfile(PACKAGE / 'test/capabilities_test.dart', app / 'test/capabilities_test.dart')
    if args.image_tasks:
        shutil.copytree(PACKAGE / 'test/fixtures/image_tasks', app / 'test/fixtures/image_tasks')
        shutil.copyfile(PACKAGE / 'test/image_tasks_test.dart', app / 'test/image_tasks_test.dart')
    if args.landmark_tasks:
        # The generator rewrote the raw fixtures with this host's decoder.
        shutil.copytree(PACKAGE / 'test/fixtures/landmark_tasks', app / 'test/fixtures/landmark_tasks')
        shutil.copyfile(PACKAGE / 'test/landmark_tasks_test.dart', app / 'test/landmark_tasks_test.dart')
    if args.segmenter_tasks:
        # Both segmenter tasks reuse the checked-in face fixtures.
        shutil.copyfile(PACKAGE / 'test/segmenter_tasks_test.dart', app / 'test/segmenter_tasks_test.dart')
    (app / 'test/native_assets').mkdir()
    shutil.copyfile(PACKAGE / 'test/native_assets/wheel_library_test.dart',
                    app / 'test/native_assets/wheel_library_test.dart')
    (app / 'integration_test').mkdir()
    for source, destination in [('flutter_smoke_test.dart.template', 'integration_test/face_test.dart'),
                                ('flutter_release_smoke.dart.template', 'lib/main.dart')]:
        content = (PACKAGE / 'tool' / source).read_text().replace(
            'VisionDelegate.values', 'const [VisionDelegate.cpu]')
        if args.object_detector and destination == 'lib/main.dart':
            content = content.replace('      report(', '      await runObjectDetectorSmoke();\n      report(')
            content += (PACKAGE / 'tool/flutter_desktop_object_smoke.dart.template').read_text()
        if args.image_tasks and destination == 'lib/main.dart':
            content = content.replace('      report(', '      await runImageTasksSmoke();\n      report(')
            content += (PACKAGE / 'tool/flutter_desktop_image_smoke.dart.template').read_text()
        if args.landmark_tasks and destination == 'lib/main.dart':
            content = content.replace('      report(', '      await runLandmarkTasksSmoke();\n      report(')
            content += (PACKAGE / 'tool/flutter_desktop_landmark_smoke.dart.template').read_text()
        if args.segmenter_tasks and destination == 'lib/main.dart':
            content = content.replace('      report(', '      await runSegmenterTasksSmoke();\n      report(')
            content += (PACKAGE / 'tool/flutter_desktop_segmenter_smoke.dart.template').read_text()
        (app / destination).write_text(content)
    env = {**os.environ, 'MEDIAPIPE_CPU_REFERENCE_DIR': str(references)}
    run(['flutter', 'pub', 'get'], app, root / 'pub.log', env)
    # Every selected task builds its own tasks per reference case.
    run(['dart', 'test', '--reporter', 'expanded'], app, root / 'dart-tests.log',
        env, timeout=2400)
    run(['flutter', 'test', '-d', target, 'integration_test/face_test.dart',
         '--reporter', 'expanded'], app, root / 'integration.log', env)
    report = {'target': target + '/x64', 'delegate': 'CPU', 'library_sha256': library_sha,
              'reference_comparison': comparisons, 'modes': {}}
    for mode in ['debug', 'release']:
        run(['flutter', 'build', target, '--' + mode], app, root / f'build-{mode}.log', env)
        bundle = app / (f'build/linux/x64/{mode}/bundle' if target == 'linux' else
                        f'build/windows/x64/runner/{mode.capitalize()}')
        libraries = [path for path in bundle.rglob('*')
                     if path.is_file() and path.suffix in ('.so', '.dll') and digest(path) == library_sha]
        if not libraries:
            raise RuntimeError(f'{mode} bundle is missing the pinned native runtime')
        deployed = root / 'deployed' / mode
        shutil.copytree(bundle, deployed)
        executable = deployed / ('mediapipe_desktop_smoke.exe' if target == 'windows'
                                  else 'mediapipe_desktop_smoke')
        log = root / f'inference-{mode}.log'
        run([executable], deployed, log, env, timeout=300)
        if 'bundled cpu Face Detector and Face Landmarker inference passed.' not in log.read_text():
            raise RuntimeError(f'{mode} app did not confirm inference')
        if args.object_detector and 'Object Detector CPU inference passed.' not in log.read_text():
            raise RuntimeError(f'{mode} app did not confirm Object Detector inference')
        if args.image_tasks and 'Image Classifier and Image Embedder CPU inference passed.' not in log.read_text():
            raise RuntimeError(f'{mode} app did not confirm image task inference')
        if args.landmark_tasks and ('Hand, Gesture, Pose and Holistic Landmarker CPU inference '
                                    'passed.') not in log.read_text():
            raise RuntimeError(f'{mode} app did not confirm landmark task inference')
        if args.segmenter_tasks and ('Image Segmenter and legacy Interactive Segmenter CPU '
                                     'inference passed.') not in log.read_text():
            raise RuntimeError(f'{mode} app did not confirm segmenter task inference')
        report['modes'][mode] = {'inference': 'passed',
                                 'bundled_libraries': [str(path.relative_to(bundle)) for path in libraries]}
    (root / 'report.json').write_text(json.dumps(report, indent=2))
    print(f'Linux/Windows CPU validation passed: {root}', flush=True)


if __name__ == '__main__':
    main()
