"""Compare the official macOS landmark runtime with pinned references.

Face, Hand, Pose, Gesture and Holistic Landmarker, Object Detector, Image
Classifier, Image Embedder and Image Segmenter run on CPU and Metal (Image
Segmenter in IMAGE mode: Google's Metal path aborts in VIDEO mode);
Interactive Segmenter Legacy on CPU. Each is compared with the official wheel's
output, generated on this machine for both CPU and GPU: the wheel's CPU results
drift between Apple CPUs, as cpu_reference.py records for every native job.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

from cpu_reference import FACE_FILES, FACE_TASKS, generate, install

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
                   'fixtures/face_landmarker', 'fixtures/landmark_tasks',
                   'fixtures/image_tasks', 'fixtures/object_detection',
                   'fixtures/segmenter_tasks'):
        shutil.copytree(PACKAGE / 'test' / folder, root / 'test' / folder,
                        dirs_exist_ok=True)
    shutil.copyfile(PACKAGE / 'test/face_landmarker_test.dart',
                    root / 'test/face_landmarker_test.dart')
    for name in ('landmark_tasks_test.dart', 'image_tasks_test.dart',
                 'object_detector_test.dart', 'segmenter_tasks_test.dart'):
        shutil.copyfile(PACKAGE / 'test' / name, root / 'test' / name)
    (root / 'models').mkdir(exist_ok=True)
    shutil.copyfile(PACKAGE / 'models/blaze_face_short_range.tflite',
                    root / 'models/blaze_face_short_range.tflite')
    shutil.copyfile(PACKAGE / 'models/face_landmarker.task',
                    root / 'models/face_landmarker.task')
    for name in ('hand_landmarker.task', 'pose_landmarker_lite.task',
                 'gesture_recognizer.task', 'holistic_landmarker.task',
                 'efficientdet_lite0.tflite', 'efficientnet_lite0.tflite',
                 'mobilenet_v3_small.tflite', 'deeplab_v3.tflite',
                 'magic_touch.tflite'):
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
      tasks: [face_detector, face_landmarker, gesture_recognizer, hand_landmarker,
              holistic_landmarker, image_classifier, image_embedder,
              image_segmenter, interactive_segmenter_legacy, object_detector,
              pose_landmarker]
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
         '--python', str(python), '--output-dir', str(gpu), '--landmark-tasks',
         '--object-detector', '--image-tasks', '--segmenter-tasks'],
        REPO, env, output / 'gpu-reference.log')

    cpu = output / 'cpu'
    oracle = generate(
        output / 'cpu-generation', cpu, 'macos/arm64',
        FACE_TASKS + [('landmark_tasks', 'landmark_tasks'),
                      ('image_tasks', 'image_tasks'),
                      ('object_detector', 'object_detection'),
                      ('segmenter_tasks', 'segmenter_tasks')],
        FACE_FILES + ['landmark_tasks/official_reference.json',
                      'image_tasks/official_reference.json',
                      'object_detection/official_reference.json',
                      'object_detection/official_video_reference.json',
                      'segmenter_tasks/official_reference.json'],
        python=python, env=env)
    print(json.dumps(oracle['comparisons'], indent=2), flush=True)

    root = test_root(output / 'consumer')
    env.update(MEDIAPIPE_CPU_REFERENCE_DIR=str(cpu),
               MEDIAPIPE_GPU_REFERENCE_DIR=str(gpu),
               MEDIAPIPE_OFFICIAL_MACOS_LANDMARK_RUNTIME='1',
               MEDIAPIPE_LANDMARK_TASKS='hand,pose,gesture,holistic')
    run(['dart', 'pub', 'get'], root, env, output / 'dart-pub-get.log')
    run(['dart', 'test', 'test/face_landmarker_test.dart',
         'test/landmark_tasks_test.dart', 'test/image_tasks_test.dart',
         'test/object_detector_test.dart', 'test/segmenter_tasks_test.dart',
         '--reporter', 'expanded'], root, env, output / 'dart-tests.log')
    print('Official macOS runtime comparisons passed for Face, Hand, Pose, '
          'Gesture, Holistic, Object Detector, Image Classifier, Image '
          'Embedder, Image Segmenter and Interactive Segmenter Legacy, all but '
          'the last on Metal too.', flush=True)


if __name__ == '__main__':
    main()
