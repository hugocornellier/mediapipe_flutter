"""Compare the official macOS landmark runtime with pinned references.

Face Landmarker runs on CPU and Metal, Hand Landmarker on CPU and Metal, and
Pose Landmarker on CPU, each against the official wheel's output: checked-in
CPU goldens, and GPU references generated on this machine.
"""
import argparse
import os
from pathlib import Path
import platform
import shutil
import subprocess

from cpu_reference import install

PACKAGE = Path(__file__).resolve().parents[1]
REPO = PACKAGE.parents[1]


def run(command, cwd, env, log):
    with log.open('w') as output:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=output,
                                stderr=subprocess.STDOUT)
    print('\n'.join(log.read_text().splitlines()[-30:]), flush=True)
    result.check_returncode()


def test_root(root):
    (root / 'test').mkdir(parents=True, exist_ok=True)
    for folder in ('support', 'fixtures/face_detection',
                   'fixtures/face_landmarker', 'fixtures/landmark_tasks'):
        shutil.copytree(PACKAGE / 'test' / folder, root / 'test' / folder,
                        dirs_exist_ok=True)
    shutil.copyfile(PACKAGE / 'test/face_landmarker_test.dart',
                    root / 'test/face_landmarker_test.dart')
    shutil.copyfile(PACKAGE / 'test/landmark_tasks_test.dart',
                    root / 'test/landmark_tasks_test.dart')
    (root / 'models').mkdir(exist_ok=True)
    shutil.copyfile(PACKAGE / 'models/blaze_face_short_range.tflite',
                    root / 'models/blaze_face_short_range.tflite')
    shutil.copyfile(PACKAGE / 'models/face_landmarker.task',
                    root / 'models/face_landmarker.task')
    for name in ('hand_landmarker.task', 'pose_landmarker_lite.task'):
        shutil.copyfile(PACKAGE / 'models' / name, root / 'models' / name)
    (root / 'pubspec.yaml').write_text(f'''name: official_macos_landmark_runtime_test
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  mediapipe_flutter_vision:
    path: {PACKAGE}
dev_dependencies:
  crypto: ^3.0.6
  test: ^1.31.0
hooks:
  user_defines:
    mediapipe_flutter_vision:
      official_macos_landmark_tasks: true
      tasks: [face_detector, face_landmarker, hand_landmarker, pose_landmarker]
''')
    return root


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--python', type=Path,
                        help='Python from the pinned official 1.0.0 wheel')
    parser.add_argument('--output-dir', type=Path,
                        default=PACKAGE / 'build/official-landmark-validation')
    args = parser.parse_args()
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise SystemExit('Official macOS landmark validation requires macOS arm64.')
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    python = args.python.absolute() if args.python else install(
        output / 'python-install', 'macos/arm64')
    env = {**os.environ, 'MPLCONFIGDIR': str(output / 'matplotlib')}

    gpu = output / 'gpu'
    run([str(python), '-B', str(PACKAGE / 'tool/prepare_gpu_reference.py'),
         '--python', str(python), '--output-dir', str(gpu), '--hand'],
        REPO, env, output / 'gpu-reference.log')

    root = test_root(output / 'consumer')
    env.update(MEDIAPIPE_GPU_REFERENCE_DIR=str(gpu),
               MEDIAPIPE_OFFICIAL_MACOS_LANDMARK_RUNTIME='1',
               MEDIAPIPE_LANDMARK_TASKS='hand,pose')
    run(['dart', 'pub', 'get'], root, env, output / 'dart-pub-get.log')
    run(['dart', 'test', 'test/face_landmarker_test.dart',
         'test/landmark_tasks_test.dart',
         '--reporter', 'expanded'], root, env, output / 'dart-tests.log')
    print('Official macOS Face, Hand and Pose runtime comparisons passed, '
          'with Face and Hand on Metal.', flush=True)


if __name__ == '__main__':
    main()
