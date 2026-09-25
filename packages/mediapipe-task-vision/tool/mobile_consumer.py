"""Create isolated Flutter apps containing the existing vision test suites."""
import json
from pathlib import Path
import re
import shutil

from build_native import PACKAGE, REPO
from test_desktop import run


def reference_deltas(log, tasks):
    """Collects the measured distance from the official reference each suite prints.

    Tolerances are unchanged; this records the headroom a passing run actually
    had, instead of learning it only when some value finally exceeds one.
    """
    found = {task: json.loads(payload) for task, payload in
             re.findall(r'MEDIAPIPE_REFERENCE_DELTAS (\S+) (\{.*\})', log)}
    missing = [task for task in tasks if task not in found]
    if missing:
        raise RuntimeError('Suites reported no reference deltas: ' + ', '.join(missing))
    return found


def prepare_app(root, platform, selected, suites, models, *, prebuilt=False,
                references=None):
    for name in ['mediapipe-core', 'mediapipe-task-vision']:
        source = PACKAGE.parent / name
        destination = root / 'packages' / name
        destination.mkdir(parents=True)
        shutil.copyfile(source / 'pubspec.yaml', destination / 'pubspec.yaml')
        for folder in ['lib', 'hook']:
            shutil.copytree(source / folder, destination / folder)
    vision = root / 'packages/mediapipe-task-vision'
    shutil.copyfile(PACKAGE / 'sdk_downloads.dart', vision / 'sdk_downloads.dart')
    app = root / 'app'
    run(['flutter', 'create', '--empty', '--no-pub', '--platforms=' + platform,
         '--project-name', 'mediapipe_' + platform + '_smoke', app], REPO, root / 'create.log')
    shutil.copytree(PACKAGE / 'test/support', app / 'test/support')
    for suite in suites:
        shutil.copyfile(PACKAGE / f'test/{suite}_test.dart', app / f'test/{suite}_test.dart')
    assets = app / 'assets'
    fixtures = assets / 'test/fixtures'
    shutil.copytree(PACKAGE / 'test/fixtures', fixtures)
    if references is not None:
        # Packaged suites read bundled assets and cannot see an environment
        # variable, so this host's official references replace the checked-in
        # goldens in place. The receipt travels with them; the suites refuse
        # references that do not match it.
        manifest = json.loads((references / 'provenance.json').read_text())
        for name in manifest['files']:
            shutil.copyfile(references / name, fixtures / name)
        shutil.copyfile(references / 'provenance.json', fixtures / 'provenance.json')
    (assets / 'models').mkdir(parents=True)
    for name in models:
        shutil.copyfile(PACKAGE / 'models' / name, assets / 'models' / name)
    for source, name in [
        (PACKAGE / 'models/blaze_face_short_range.tflite', 'model.tflite'),
        (PACKAGE / 'models/face_landmarker.task', 'face_landmarker.task'),
        (PACKAGE / 'test/fixtures/face_detection/portrait-301x209.rgb', 'portrait.rgb'),
    ]:
        shutil.copyfile(source, assets / name)
    asset_files = sorted(p.relative_to(app).as_posix() for p in assets.rglob('*') if p.is_file())
    (app / 'pubspec.yaml').write_text('''name: mediapipe_''' + platform + '''_smoke
version: 0.1.0+1
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  flutter:
    sdk: flutter
  mediapipe_flutter_vision:
    path: ../packages/mediapipe-task-vision
dev_dependencies:
  crypto: ^3.0.6
  test: ^1.31.0
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
hooks:
  user_defines:
    mediapipe_flutter_vision:
      # The source-built face runtime, not Google's mobile SDKs (the default).
      official_android_sdk: false
      official_ios_sdk: false
      prebuilt: ''' + str(prebuilt).lower() + '''
      tasks: [''' + ', '.join(selected) + ''']
flutter:
  assets:
''' + ''.join(f'    - {name}\n' for name in asset_files))
    integration = app / 'integration_test'
    integration.mkdir()
    (integration / 'tasks_test.dart').write_text('''import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
''' + ''.join(f"import '../test/{suite}_test.dart' as suite{i};\n"
              for i, suite in enumerate(suites)) + '''
Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final directory = await Directory.systemTemp.createTemp('mediapipe-fixtures-');
  final previous = Directory.current;
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  for (final name in manifest.listAssets().where((name) => name.startsWith('assets/'))) {
    final bytes = await rootBundle.load(name);
    final file = File('${directory.path}/${name.substring('assets/'.length)}');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
  }
  Directory.current = directory;
  tearDownAll(() async {
    Directory.current = previous;
    await directory.delete(recursive: true);
  });
''' + ''.join(f"  group('{suite}', suite{i}.main);\n" for i, suite in enumerate(suites)) + '}\n')
    smoke = (PACKAGE / 'tool/flutter_release_smoke.dart.template').read_text().replace(
        'VisionDelegate.values', 'const [VisionDelegate.cpu]')
    (app / 'lib/main.dart').write_text(smoke)
    return app, vision
