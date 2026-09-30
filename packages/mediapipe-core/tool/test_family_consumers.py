"""Each task family alone, and all three together, in fresh apps.

Builds four apps from pub.dev-shaped package copies: vision only, text only,
audio only, and vision + text + audio. Each lists only the settings it needs,
downloads its models through the family's own pins, and runs one inference per
task in an integration test on macOS or the iOS Simulator. Source-build tools
are blocked. The combined app must bundle exactly the frameworks the single
apps do, each once: the families share core's runtime rather than carrying
copies of it. Every app also runs a `dart run` script, which builds its hooks
for this Mac with its settings. On macOS a fifth app uses every family without
core's engine opt-in: it builds, and the engine tasks name the opt-in.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from consumer_packages import copy_package

CORE = Path(__file__).resolve().parents[1]
REPO = CORE.parents[1]
SAMPLES = REPO / 'gallery/assets/samples'
BLOCKED = ('bazel', 'bazelisk', 'cmake', 'ninja', 'python', 'python3')

FAMILIES = {
    'vision': {
        'package': 'mediapipe-task-vision',
        'import': 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart',
        'models': """  await downloadVerified(DownloadAsset(url: blazeFaceShortRangeUrl, sha256: blazeFaceShortRangeSha256), File('../models/blaze_face_short_range.tflite'));
  await downloadVerified(DownloadAsset(url: efficientDetLite0Url, sha256: efficientDetLite0Sha256), File('../models/efficientdet_lite0.tflite'));
""",
        'models_import': 'package:mediapipe_flutter_vision/models.dart',
        'model_files': ['blaze_face_short_range.tflite', 'efficientdet_lite0.tflite'],
        'samples': ['portrait.jpg'],
        'test': """  testWidgets('vision: Face Detector and Object Detector', (tester) async {
    await tester.runAsync(() async {
      final image = VisionImage.fromFile(await file('portrait.jpg'));
      final faces = await FaceDetector.create(FaceDetectorOptions(
          modelBytes: await asset('blaze_face_short_range.tflite')));
      try {
        final result = await faces.detectImage(image);
        expect(result.detections, hasLength(1));
        report['face_detector'] = result.detections.single.categories.first.score;
      } finally {
        await faces.dispose();
      }
      final objects = await ObjectDetector.create(ObjectDetectorOptions(
          modelBytes: await asset('efficientdet_lite0.tflite'), maxResults: 1));
      try {
        final result = await objects.detectImage(image);
        expect(result.detections.single.categories.first.categoryName, 'person');
        report['object_detector'] = result.detections.single.categories.first.score;
      } finally {
        await objects.dispose();
      }
    });
  });
""",
    },
    'text': {
        'package': 'mediapipe-task-text',
        'import': 'package:mediapipe_flutter_text/mediapipe_flutter_text.dart',
        'models': """  await downloadVerified(bertClassifierModel, File('../models/bert_classifier.tflite'));
""",
        'models_import': 'package:mediapipe_flutter_text/models.dart',
        'model_files': ['bert_classifier.tflite'],
        'samples': [],
        'test': """  testWidgets('text: Text Classifier', (tester) async {
    await tester.runAsync(() async {
      final task = await TextClassifier.create(
          TextClassifierOptions.fromAssetBuffer(await asset('bert_classifier.tflite')));
      try {
        final result = await task.classify('Hello, world!');
        final top = result.classifications.single.categories.first;
        expect(top.categoryName, 'positive');
        report['text_classifier'] = top.score;
      } finally {
        await task.dispose();
      }
    });
  });
""",
    },
    'audio': {
        'package': 'mediapipe-task-audio',
        'import': 'package:mediapipe_flutter_audio/mediapipe_flutter_audio.dart',
        'models': """  await downloadVerified(DownloadAsset(url: yamnetUrl, sha256: yamnetSha256), File('../models/yamnet.tflite'));
""",
        'models_import': 'package:mediapipe_flutter_audio/models.dart',
        'model_files': ['yamnet.tflite'],
        'samples': ['speech_16000_hz_mono.wav'],
        'test': """  testWidgets('audio: Audio Classifier', (tester) async {
    await tester.runAsync(() async {
      final task = await AudioClassifier.create(AudioClassifierOptions(
          modelBytes: await asset('yamnet.tflite'), maxResults: 1));
      try {
        final chunks = await task.classify(
            decodeWav(await asset('speech_16000_hz_mono.wav')));
        expect(chunks.first.categories.first.name, 'Speech');
        report['audio_classifier'] = chunks.first.categories.first.score;
      } finally {
        await task.dispose();
      }
    });
  });
""",
    },
}

APPS = {
    'vision_only': ['vision'],
    'text_only': ['text'],
    'audio_only': ['audio'],
    'all_families': ['vision', 'text', 'audio'],
}

# macOS only: every family without core's opt-in still builds, and `dart run`
# still works; the engine tasks name the opt-in when created.
WITHOUT_ENGINE = """  testWidgets('without the opt-in, engine tasks name it', (tester) async {
    await tester.runAsync(() async {
      final faces = await FaceDetector.create(FaceDetectorOptions(
          modelBytes: await asset('blaze_face_short_range.tflite')));
      try {
        final result = await faces.detectImage(
            VisionImage.fromFile(await file('portrait.jpg')));
        expect(result.detections, hasLength(1));
        report['face_detector'] = result.detections.single.categories.first.score;
      } finally {
        await faces.dispose();
      }
      final optIn = isA<UnsupportedError>().having((e) => e.message, 'message',
          allOf(contains('On macOS'), contains('tasks_runtime: true')));
      await expectLater(ObjectDetector.create(ObjectDetectorOptions(
          modelBytes: await asset('efficientdet_lite0.tflite'))), throwsA(optIn));
      await expectLater(TextClassifier.create(TextClassifierOptions.fromAssetBuffer(
          await asset('bert_classifier.tflite'))), throwsA(optIn));
      await expectLater(AudioClassifier.create(AudioClassifierOptions(
          modelBytes: await asset('yamnet.tflite'))), throwsA(optIn));
      report['engine_tasks'] = 'named the opt-in';
    });
  });
"""


def settings(families, platform, engine=True):
    """The least an app writes: vision's task list, and on macOS the opt-in
    to Google's 95 MB engine that text, audio and Object Detector run on."""
    lines = []
    if platform == 'macos' and engine:
        lines += ['    mediapipe_flutter_core:', '      tasks_runtime: true']
    if 'vision' in families:
        lines += ['    mediapipe_flutter_vision:', '      tasks: [face_detector, object_detector]']
    return 'hooks:\n  user_defines:\n' + '\n'.join(lines) + '\n' if lines else ''


def download_models(root, env):
    """Fetches every model once through the families' own pins, in one
    host-side package, so each app copies only the models it uses."""
    downloader = root / 'downloader'
    (downloader / 'bin').mkdir(parents=True)
    (root / 'models').mkdir()
    dependencies = ''.join(
        f"  mediapipe_flutter_{family}:\n    path: ../packages/{spec['package']}\n"
        for family, spec in FAMILIES.items())
    (downloader / 'pubspec.yaml').write_text(f"""name: downloader
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  flutter:
    sdk: flutter
  mediapipe_flutter_core:
    path: ../packages/mediapipe-core
{dependencies}hooks:
  user_defines:
    mediapipe_flutter_core:
      tasks_runtime: true
""")
    (downloader / 'bin/download_models.dart').write_text(
        "import 'dart:io';\nimport 'package:mediapipe_flutter_core/native_assets.dart';\n"
        + ''.join(f"import '{spec['models_import']}';\n" for spec in FAMILIES.values())
        + 'Future<void> main() async {\n'
        + ''.join(spec['models'] for spec in FAMILIES.values()) + '}\n')
    run(['flutter', 'pub', 'get'], downloader, env, root / 'downloader-pub.log')
    run(['dart', 'run', 'bin/download_models.dart'], downloader, env, root / 'models.log')


def create_app(root, name, families, platform, env, engine=True):
    app = root / name
    subprocess.run(['flutter', 'create', '--platforms=' + ('macos' if platform == 'macos' else 'ios'),
                    '--empty', '--no-pub', '--project-name', name, str(app)],
                   env=env, check=True, capture_output=True)
    dependencies = ''.join(
        f"  mediapipe_flutter_{family}:\n    path: ../packages/{FAMILIES[family]['package']}\n"
        for family in families)
    (app / 'pubspec.yaml').write_text(f"""name: {name}
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  flutter:
    sdk: flutter
{dependencies}dev_dependencies:
  integration_test:
    sdk: flutter
  flutter_test:
    sdk: flutter
flutter:
  assets:
    - assets/
{settings(families, platform, engine)}""")
    # `dart run` builds the app's hooks for this Mac with the app's settings.
    (app / 'bin').mkdir()
    (app / 'bin/hello.dart').write_text("void main() => print('hello');\n")
    (app / 'assets').mkdir()
    for family in families:
        for sample in FAMILIES[family]['samples']:
            shutil.copyfile(SAMPLES / sample, app / 'assets' / sample)
    for family in families:
        for model in FAMILIES[family]['model_files']:
            shutil.copyfile(root / 'models' / model, app / 'assets' / model)
    (app / 'integration_test').mkdir()
    (app / 'integration_test/families_test.dart').write_text(
        "import 'dart:convert';\nimport 'dart:io';\n"
        "import 'package:flutter/services.dart';\n"
        "import 'package:flutter_test/flutter_test.dart';\n"
        "import 'package:integration_test/integration_test.dart';\n"
        + ''.join(f"import '{FAMILIES[f]['import']}';\n" for f in families)
        + """
final report = <String, Object?>{};

Future<Uint8List> asset(String name) async {
  final data = await rootBundle.load('assets/' + name);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<String> file(String name) async {
  final file = File('${Directory.systemTemp.path}/$name');
  await file.writeAsBytes(await asset(name));
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
"""
        + (''.join(FAMILIES[f]['test'] for f in families) if engine else WITHOUT_ENGINE)
        + """  tearDownAll(() => print('FAMILY_REPORT ' + jsonEncode(report)));
}
""")
    if platform == 'macos':
        config = app / 'macos/Runner/Configs/AppInfo.xcconfig'
        config.write_text(config.read_text() + '\nARCHS = arm64\nEXCLUDED_ARCHS = x86_64\n')
        project = app / 'macos/Runner.xcodeproj/project.pbxproj'
        project.write_text(project.read_text().replace(
            'MACOSX_DEPLOYMENT_TARGET = 10.15;', 'MACOSX_DEPLOYMENT_TARGET = 14.0;'))
    return app


def run(command, app, env, log):
    with log.open('w') as output:
        result = subprocess.run(command, cwd=app, env=env, stdout=output,
                                stderr=subprocess.STDOUT, text=True)
    if result.returncode:
        raise RuntimeError(f"{' '.join(command)} failed in {app.name}; see {log}")
    return log.read_text()


def frameworks(app, platform):
    if platform == 'macos':
        bundle = next((app / 'build/macos/Build/Products/Debug').glob('*.app'))
        folder = bundle / 'Contents/Frameworks'
    else:
        folder = app / 'build/ios/iphonesimulator/Runner.app/Frameworks'
    return sorted(path.name for path in folder.iterdir()) if folder.exists() else []


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['macos', 'ios-simulator'], required=True)
    parser.add_argument('--device', help='Booted iOS Simulator UUID (ios-simulator)')
    parser.add_argument('--keep', action='store_true', help='Keep the apps afterwards')
    args = parser.parse_args()
    device = 'macos' if args.platform == 'macos' else args.device
    if not device:
        parser.error('--device is required for the iOS Simulator')

    build = REPO / 'build/codex-tmp'
    build.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix=f'family-consumers-{args.platform}-', dir=build))
    for name in ('mediapipe-core', 'mediapipe-task-vision', 'mediapipe-task-text', 'mediapipe-task-audio'):
        copy_package(REPO / 'packages' / name, root / 'packages' / name)
    guards = root / 'blocked-tools'
    guards.mkdir()
    blocked_log = root / 'blocked-tools.log'
    for name in BLOCKED:
        path = guards / name
        path.write_text('#!/bin/sh\necho "Unexpected build tool: $0" >> "$MEDIAPIPE_BLOCKED_TOOLS_LOG"\nexit 97\n')
        path.chmod(0o755)
    env = {**os.environ, 'PATH': str(guards) + os.pathsep + os.environ['PATH'],
           'MEDIAPIPE_BLOCKED_TOOLS_LOG': str(blocked_log)}

    results = {}
    download_models(root, env)
    try:
        apps = [(name, families, True) for name, families in APPS.items()]
        if args.platform == 'macos':
            apps.append(('without_engine', ['vision', 'text', 'audio'], False))
        for name, families, engine in apps:
            print(f'{name}: {", ".join(families)}', flush=True)
            app = create_app(root, name, families, args.platform, env, engine)
            run(['flutter', 'pub', 'get'], app, env, root / f'{name}-pub.log')
            if 'hello' not in run(['dart', 'run', 'bin/hello.dart'], app, env,
                                  root / f'{name}-dart-run.log'):
                raise RuntimeError(f'dart run printed nothing in {name}')
            output = run(['flutter', 'test', '-d', device, 'integration_test/families_test.dart',
                          '--reporter', 'expanded'], app, env, root / f'{name}-test.log')
            reports = [line.split('FAMILY_REPORT ', 1)[1] for line in output.splitlines()
                       if 'FAMILY_REPORT ' in line]
            if 'All tests passed!' not in output or not reports:
                raise RuntimeError(f'{name} did not pass; see {root / (name + "-test.log")}')
            results[name] = {'families': families, 'scores': json.loads(reports[-1]),
                             'frameworks': frameworks(app, args.platform),
                             'settings': settings(families, args.platform, engine).strip().splitlines(),
                             'host_dart_run': 'passed'}
            if 'Class MPPMetalSharedResources is implemented in both' in output:
                raise RuntimeError(f'{name} loaded two copies of MediaPipe')
            print(f"  passed: {results[name]['scores']}", flush=True)
        if blocked_log.exists():
            raise RuntimeError('A source-build tool ran: ' + blocked_log.read_text())
        union = sorted({f for name in ('vision_only', 'text_only', 'audio_only')
                        for f in results[name]['frameworks']})
        combined = results['all_families']['frameworks']
        if combined != union:
            raise RuntimeError(f'The combined app bundles {combined}, the single apps {union}')
        report = {'platform': args.platform, 'apps': results,
                  'combined_equals_union_of_singles': True,
                  'blocked_build_tools': list(BLOCKED)}
        (root / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, indent=2), flush=True)
        print('Family consumers passed: ' + str(root / 'report.json'), flush=True)
    finally:
        # Logs and the report stay; the apps and copies are gigabytes.
        if not args.keep:
            for name in [*APPS, 'without_engine', 'downloader', 'models', 'packages', 'blocked-tools']:
                shutil.rmtree(root / name, ignore_errors=True)


if __name__ == '__main__':
    main()
