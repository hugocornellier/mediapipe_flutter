"""Fresh macOS Flutter debug/release consumer with public, verified downloads.

Copies only publishable Dart packages: no native builds or model cache. Downloads
the pinned models and runtime, then compares official outputs while face tasks,
MagicTouch, EmbeddingGemma and Proofreader coexist. Bazel/CMake/Python are blocked
in builds. Xcode's Clang compiles only the small callback-copy adapter.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

PACKAGE = Path(__file__).resolve().parents[1]
REPO = PACKAGE.parents[1]


def main():
    build = REPO / 'build/codex-tmp'
    build.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix='embedding-consumer-', dir=build))
    packages = root / 'packages'
    for name in ('mediapipe-core', 'mediapipe-task-text', 'mediapipe-task-vision'):
        source, target = REPO / 'packages' / name, packages / name
        target.mkdir(parents=True)
        shutil.copyfile(source / 'pubspec.yaml', target / 'pubspec.yaml')
        shutil.copytree(source / 'lib', target / 'lib')
        shutil.copytree(source / 'hook', target / 'hook')
        if (source / 'native').is_dir():
            shutil.copytree(source / 'native', target / 'native')
        if (source / 'sdk_downloads.dart').is_file():
            shutil.copyfile(source / 'sdk_downloads.dart', target / 'sdk_downloads.dart')
    guards = root / 'blocked-tools'
    guards.mkdir()
    blocked_log = root / 'blocked-tools.log'
    for name in ('bazel', 'bazelisk', 'cmake', 'ninja', 'python', 'python3'):
        path = guards / name
        path.write_text('#!/bin/sh\necho "Unexpected build tool: $0" >> "$MEDIAPIPE_BLOCKED_TOOLS_LOG"\nexit 97\n')
        path.chmod(0o755)
    env = {**os.environ, 'PATH': str(guards) + os.pathsep + os.environ['PATH'],
           'MEDIAPIPE_BLOCKED_TOOLS_LOG': str(blocked_log)}
    app = root / 'app'
    subprocess.run(['flutter', 'create', '--platforms=macos', '--empty', '--no-pub',
                    '--project-name', 'embedding_consumer', str(app)], env=env, check=True)
    (app / 'pubspec.yaml').write_text('''name: embedding_consumer
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  flutter:
    sdk: flutter
  mediapipe_flutter_core:
    path: ../packages/mediapipe-core
  mediapipe_flutter_text:
    path: ../packages/mediapipe-task-text
  mediapipe_flutter_vision:
    path: ../packages/mediapipe-task-vision
dev_dependencies:
  integration_test:
    sdk: flutter
  flutter_test:
    sdk: flutter
flutter:
  assets:
    - assets/
hooks:
  user_defines:
    mediapipe_flutter_core:
      tasks_runtime: true
    mediapipe_flutter_vision:
      tasks: [face_detector, face_landmarker, interactive_segmenter]
      prebuilt: true
''')
    assets = app / 'assets'
    assets.mkdir()
    shutil.copyfile(PACKAGE / 'test/fixtures/embedding_gemma/official_reference.json', assets / 'embedding_reference.json')
    shutil.copyfile(PACKAGE / 'test/fixtures/proofreader/official_reference.json', assets / 'proofreader_reference.json')
    vision = REPO / 'packages/mediapipe-task-vision'
    for name in ('animals-299x150.rgb', 'raw-dog.f32.gz'):
        shutil.copyfile(vision / 'test/fixtures/interactive_segmentation' / name, assets / name)
    shutil.copyfile(vision / 'test/fixtures/face_detection/landmark-ex1.jpg', assets / 'landmark-ex1.jpg')
    shutil.copyfile(PACKAGE / 'tool/flutter_embedding_validation.dart.template', app / 'lib/validation.dart')
    (app / 'bin').mkdir()
    (app / 'bin/download_models.dart').write_text('''import 'dart:io';
import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:mediapipe_flutter_text/models.dart';
import 'package:mediapipe_flutter_vision/models.dart';
Future<void> main() async {
  await downloadVerified(embeddingGemmaModel, File('assets/embedding_gemma.task'));
  await downloadVerified(proofreaderModel, File('assets/proofread_quant_200m.litertlm'));
  await downloadVerified((url: interactiveSegmenterModelUrl, sha256: interactiveSegmenterModelSha256), File('assets/interactive_segmentation.task'));
  await downloadVerified((url: blazeFaceShortRangeUrl, sha256: blazeFaceShortRangeSha256), File('assets/blaze_face_short_range.tflite'));
  await downloadVerified((url: faceLandmarkerUrl, sha256: faceLandmarkerSha256), File('assets/face_landmarker.task'));
}
''')
    (app / 'lib/main.dart').write_text('''import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'validation.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    stdout.writeln('EMBEDDING_REPORT ' + jsonEncode(await validateEmbedding()));
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\\n$stack');
    exit(1);
  }
}
''')
    (app / 'integration_test').mkdir()
    (app / 'integration_test/embedding_test.dart').write_text('''import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../lib/validation.dart';
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('official EmbeddingGemma and vision coexist on macOS CPU', (tester) async {
    final report = await validateEmbedding();
    expect(report['reference_cases'], 17);
    expect((report['proofreader'] as Map)['reference_cases'], 9);
    print('EMBEDDING_DEBUG_REPORT ' + jsonEncode(report));
  });
}
''')
    config = app / 'macos/Runner/Configs/AppInfo.xcconfig'
    config.write_text(config.read_text() + '\nARCHS = arm64\nEXCLUDED_ARCHS = x86_64\n')
    project = app / 'macos/Runner.xcodeproj/project.pbxproj'
    project.write_text(project.read_text().replace('MACOSX_DEPLOYMENT_TARGET = 10.15;', 'MACOSX_DEPLOYMENT_TARGET = 14.0;'))

    def run(command, log_name):
        print('Running: ' + ' '.join(command), flush=True)
        with (root / log_name).open('w') as log:
            process = subprocess.Popen(command, cwd=app, env=env, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, text=True)
            for line in process.stdout:
                print(line, end='', flush=True)
                log.write(line)
            if process.wait():
                raise RuntimeError(f'{command} failed; see {root / log_name}')

    print('Fresh consumer: ' + str(root), flush=True)
    run(['flutter', 'pub', 'get'], 'pub-get.log')
    run(['dart', 'run', 'bin/download_models.dart'], 'downloads.log')
    run(['flutter', 'test', '-d', 'macos', 'integration_test/embedding_test.dart', '--reporter', 'expanded'], 'debug.log')
    run(['flutter', 'build', 'macos', '--release'], 'release-build.log')
    bundle = app / 'build/macos/Build/Products/Release/embedding_consumer.app'
    result = subprocess.run([str(bundle / 'Contents/MacOS/embedding_consumer')], cwd=app,
                            env=env, capture_output=True, text=True, timeout=120)
    (root / 'release.log').write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f'Release inference failed: {result.stderr}')
    reports = [line.removeprefix('EMBEDDING_REPORT ') for line in result.stdout.splitlines()
               if line.startswith('EMBEDDING_REPORT ')]
    if len(reports) != 1:
        raise RuntimeError('Release app did not return a validation report.')
    report = json.loads(reports[0])
    frameworks = [path.name for path in (bundle / 'Contents/Frameworks').iterdir()]
    if sum('interactive_segmenter' in name for name in frameworks) != 1:
        raise RuntimeError(f'Shared runtime must be bundled exactly once: {frameworks}')
    if sum('mediapipe_text_stream' in name for name in frameworks) != 1:
        raise RuntimeError(f'Callback adapter must be bundled exactly once: {frameworks}')
    if any(name in ('libtext.framework', 'text.framework') for name in frameworks):
        raise RuntimeError('Legacy text runtime was bundled in a modern app.')
    if blocked_log.exists() or any(packages.rglob('build/native')):
        raise RuntimeError('Native build tools were accessed by the fresh consumer.')
    manifests = [json.loads(p.read_text()) for p in (app / '.dart_tool').rglob('manifest.json')]
    if not any(m.get('release') == 'interactive-segmenter-v1.0.1-1' for m in manifests):
        raise RuntimeError('Missing verified public runtime provenance.')
    if 'Class MPPMetalSharedResources is implemented in both' in result.stderr:
        raise RuntimeError('Duplicate Objective-C runtime classes were loaded.')
    report.update({'debug_inference': 'passed', 'release_inference': 'passed',
                   'source': 'public-release', 'mediapipe_source_build': False,
                   'blocked_build_tools': ['bazel', 'bazelisk', 'cmake', 'ninja', 'python', 'python3'],
                   'callback_adapter': 'compiled with system Clang',
                   'frameworks': frameworks, 'shared_runtime_copies': 1})
    (root / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2), flush=True)
    print('Fresh macOS consumer passed: ' + str(root / 'report.json'), flush=True)


if __name__ == '__main__':
    main()
