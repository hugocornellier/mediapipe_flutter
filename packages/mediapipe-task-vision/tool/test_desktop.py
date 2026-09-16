"""Validate official CPU references and isolated Flutter desktop consumers."""
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
    command = [shutil.which(command[0]) or command[0], *map(str, command[1:])]
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
    system = platform.system()
    target = {'Linux': 'linux', 'Windows': 'windows'}.get(system)
    if target is None or platform.machine().lower() not in ('amd64', 'x86_64'):
        raise SystemExit('This validation requires Linux x64 or Windows x64.')
    build = REPO / 'build/codex-tmp'
    build.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix=f'desktop-{target}-', dir=build))
    print(f'Validation artifacts: {root}', flush=True)
    pins = (PACKAGE / 'sdk_downloads.dart').read_text()
    row = re.search(r"'" + target + r"/x64': VisionWheelRelease\((.*?)\n  \),", pins, re.S).group(1)
    wheel_url = dart_strings(re.search(r'url:(.*?),', row, re.S).group(1))
    wheel_sha = re.search(r"sha256:\s*'([a-f0-9]+)'", row).group(1)
    library_sha = re.search(r"librarySha256:\s*'([a-f0-9]+)'", row).group(1)
    model_pins = (PACKAGE / 'lib/models.dart').read_text()
    for prefix, name in [('blazeFaceShortRange', 'blaze_face_short_range.tflite'),
                         ('faceLandmarker', 'face_landmarker.task')]:
        url = dart_strings(re.search(r'const ' + prefix + r'Url\s*=(.*?);', model_pins, re.S).group(1))
        sha = dart_strings(re.search(r'const ' + prefix + r'Sha256\s*=(.*?);', model_pins, re.S).group(1))
        download(url, sha, PACKAGE / 'models' / name)

    python_env = root / 'python'
    run([sys.executable, '-m', 'venv', python_env], REPO, root / 'venv.log')
    python = python_env / ('Scripts/python.exe' if system == 'Windows' else 'bin/python')
    run([python, '-m', 'pip', 'install', '--disable-pip-version-check',
         wheel_url + '#sha256=' + wheel_sha], REPO, root / 'pip.log')
    references = root / 'reference'
    references.mkdir()
    files = ['face_detection/official_reference.json',
             'face_detection/official_video_reference.json',
             'face_landmarker/official_reference.json']
    for task, folder in [('face_detector', 'face_detection'),
                         ('face_landmarker', 'face_landmarker')]:
        run([python, '-B', PACKAGE / f'tool/generate_{task}_reference.py',
             '--output-dir', references / folder], REPO, root / f'{task}-reference.log')
    from prepare_gpu_reference import difference
    comparisons = {}
    for name in files:
        reference = json.loads((references / name).read_text())
        if reference['library_sha256'] != library_sha:
            raise RuntimeError('Independent reference used a different native library')
        comparisons[name] = difference(json.loads((PACKAGE / 'test/fixtures' / name).read_text()),
                                       reference)
    (references / 'provenance.json').write_text(json.dumps({
        'runtime': 'mediapipe==1.0.0', 'source': 'official-python-api',
        'delegate': 'CPU', 'target': target + '/x64',
        'library_sha256': library_sha, 'wheel_sha256': wheel_sha,
        'files': {name: digest(references / name) for name in files},
        'checked_in_reference_differences': comparisons,
    }, indent=2))

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
      tasks: [face_detector, face_landmarker]
flutter:
  assets:
    - assets/model.tflite
    - assets/face_landmarker.task
    - assets/portrait.rgb
''')
    assets = app / 'assets'
    assets.mkdir()
    for source, name in [(PACKAGE / 'models/blaze_face_short_range.tflite', 'model.tflite'),
                         (PACKAGE / 'models/face_landmarker.task', 'face_landmarker.task'),
                         (PACKAGE / 'test/fixtures/face_detection/portrait-301x209.rgb', 'portrait.rgb')]:
        shutil.copyfile(source, assets / name)
    shutil.copytree(PACKAGE / 'models', app / 'models',
                    ignore=shutil.ignore_patterns('*.xnnpack_cache'))
    for folder in ['fixtures/face_detection', 'fixtures/face_landmarker', 'support']:
        shutil.copytree(PACKAGE / 'test' / folder, app / 'test' / folder)
    for name in ['face_detector_test.dart', 'face_landmarker_test.dart', 'pixel_conversion_test.dart']:
        shutil.copyfile(PACKAGE / 'test' / name, app / 'test' / name)
    (app / 'test/native_assets').mkdir()
    shutil.copyfile(PACKAGE / 'test/native_assets/wheel_library_test.dart',
                    app / 'test/native_assets/wheel_library_test.dart')
    (app / 'integration_test').mkdir()
    for source, destination in [('flutter_smoke_test.dart.template', 'integration_test/face_test.dart'),
                                ('flutter_release_smoke.dart.template', 'lib/main.dart')]:
        content = (PACKAGE / 'tool' / source).read_text().replace(
            'VisionDelegate.values', 'const [VisionDelegate.cpu]')
        (app / destination).write_text(content)
    env = {**os.environ, 'MEDIAPIPE_CPU_REFERENCE_DIR': str(references)}
    run(['flutter', 'pub', 'get'], app, root / 'pub.log', env)
    run(['dart', 'test', '--reporter', 'expanded'], app, root / 'dart-tests.log', env)
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
        run([executable], deployed, log, env, timeout=90)
        if 'bundled cpu Face Detector and Face Landmarker inference passed.' not in log.read_text():
            raise RuntimeError(f'{mode} app did not confirm inference')
        report['modes'][mode] = {'inference': 'passed',
                                 'bundled_libraries': [str(path.relative_to(bundle)) for path in libraries]}
    (root / 'report.json').write_text(json.dumps(report, indent=2))
    print(f'Linux/Windows CPU validation passed: {root}', flush=True)


if __name__ == '__main__':
    main()
