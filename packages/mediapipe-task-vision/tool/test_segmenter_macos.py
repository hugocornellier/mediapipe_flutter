"""Verify an isolated, opt-in Flutter consumer in debug and release.

No package-local native libraries, source tools or Python runtime are copied.
--local-release serves the pinned candidate before publication; default tests
the public release. The release app also prints reproducible CPU measurements.
"""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from test_flutter_macos import PACKAGE
from test_prebuilt_macos import release_server

TAG = "interactive-segmenter-v1.0.1-1"
NAME = "mediapipe-interactive-segmenter-1.0.1-macos-arm64.tar.gz"


def verify(root, local_urls=None):
    packages = root / "packages"
    for name in ("mediapipe-core", "mediapipe-task-vision"):
        source = PACKAGE.parent / name
        target = packages / name
        target.mkdir(parents=True)
        shutil.copyfile(source / "pubspec.yaml", target / "pubspec.yaml")
        shutil.copytree(source / "lib", target / "lib")
    vision = packages / PACKAGE.name
    shutil.copytree(PACKAGE / "hook", vision / "hook")
    shutil.copyfile(PACKAGE / "sdk_downloads.dart", vision / "sdk_downloads.dart")
    if local_urls:
        pins = vision / "sdk_downloads.dart"
        def replace_url(match):
            url = "".join(re.findall(r"'([^']*)'", match.group()))
            if url.endswith("/" + NAME):
                return f"url: '{local_urls[NAME]}',"
            return match.group()
        pins.write_text(re.sub(r"url:\s*(?:'[^']*'\s*)+,",
                               replace_url, pins.read_text()))

    guards = root / "blocked-tools"
    guards.mkdir()
    log = root / "blocked-tools.log"
    for name in ("bazel", "bazelisk", "cmake", "ninja", "python", "python3"):
        path = guards / name
        path.write_text('#!/bin/sh\necho "Unexpected build tool: $0" >> '
                        '"$MEDIAPIPE_BLOCKED_TOOLS_LOG"\nexit 97\n')
        path.chmod(0o755)
    env = {**os.environ, "PATH": str(guards) + os.pathsep + os.environ["PATH"],
           "MEDIAPIPE_BLOCKED_TOOLS_LOG": str(log)}
    app = root / "app"
    subprocess.run([
        "flutter", "create", "--platforms=macos", "--empty", "--no-pub",
        "--project-name", "segmenter_consumer", str(app),
    ], env=env, check=True)
    (app / "pubspec.yaml").write_text("""name: segmenter_consumer
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  flutter:
    sdk: flutter
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
    mediapipe_flutter_vision:
      tasks: [interactive_segmenter]
      prebuilt: true
""")
    assets = app / "assets"
    assets.mkdir()
    shutil.copyfile(PACKAGE / "models/interactive_segmentation.task",
                    assets / "interactive_segmentation.task")
    for name in ("animals-299x150.rgb", "cats_and_dogs.jpg",
                 "official_reference.json", "raw-dog.f32.gz", "raw-negative.f32.gz"):
        shutil.copyfile(PACKAGE / "test/fixtures/interactive_segmentation" / name,
                        assets / name)
    shutil.copyfile(PACKAGE / "tool/flutter_segmenter_validation.dart.template",
                    app / "lib/validation.dart")
    shutil.copyfile(PACKAGE / "example_segmenter/lib/mask_overlay.dart",
                    app / "lib/mask_overlay.dart")
    (app / "lib/main.dart").write_text("""import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'validation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final report = await validateSegmenter(benchmark: true);
    stdout.writeln('SEGMENTER_REPORT ' + jsonEncode(report));
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\\n$stack');
    exit(1);
  }
}
""")
    (app / "integration_test").mkdir()
    (app / "integration_test/segmenter_test.dart").write_text(
        """import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../lib/validation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('official MagicTouch masks in a fresh Flutter app', (tester) async {
    final report = await validateSegmenter();
    expect(report['reference_cases'], 2);
  });
}
""")
    config = app / "macos/Runner/Configs/AppInfo.xcconfig"
    config.write_text(config.read_text() + "\nARCHS = arm64\nEXCLUDED_ARCHS = x86_64\n")
    project = app / "macos/Runner.xcodeproj/project.pbxproj"
    project.write_text(project.read_text().replace(
        "MACOSX_DEPLOYMENT_TARGET = 10.15;", "MACOSX_DEPLOYMENT_TARGET = 14.0;"))

    def run(args):
        subprocess.run(args, cwd=app, env=env, check=True)

    print(f"Fresh segmenter consumer: {root}", flush=True)
    run(["flutter", "pub", "get"])
    run(["flutter", "test", "-d", "macos", "integration_test/segmenter_test.dart",
         "--reporter", "expanded"])
    run(["flutter", "build", "macos", "--release"])
    bundle = app / "build/macos/Build/Products/Release/segmenter_consumer.app"
    executable = bundle / "Contents/MacOS/segmenter_consumer"
    result = subprocess.run([str(executable)], cwd=app, env=env, check=True,
                            capture_output=True, text=True, timeout=120)
    (root / "release.log").write_text(result.stdout + result.stderr)
    print(result.stdout, flush=True)
    reports = [line.removeprefix("SEGMENTER_REPORT ")
               for line in result.stdout.splitlines()
               if line.startswith("SEGMENTER_REPORT ")]
    if len(reports) != 1:
        raise RuntimeError("Release app did not produce its validation report")
    report = json.loads(reports[0])
    manifests = list((app / ".dart_tool").rglob("manifest.json"))
    releases = {json.loads(path.read_text()).get("release") for path in manifests}
    if TAG not in releases or any(
            value and value.startswith("face-") for value in releases):
        raise RuntimeError(f"Unexpected downloaded tasks: {releases}")
    framework_names = [path.name for path in (bundle / "Contents/Frameworks").iterdir()]
    if any("face_detector" in name or "face_landmarker" in name
           for name in framework_names):
        raise RuntimeError("Opt-in segmenter consumer bundled a face library")
    if (vision / "build/native").exists() or (vision / "tool").exists() or log.exists():
        raise RuntimeError("Consumer unexpectedly accessed native source/build tools")
    report.update({"debug_inference": "passed", "release_inference": "passed",
                   "native_build_tools_invoked": False, "release": TAG,
                   "source": "local-candidate" if local_urls else "public-release",
                   "frameworks": framework_names})
    (root / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("Fresh consumer passed; report: " + str(root / "report.json"), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--local-release", type=Path)
    args = parser.parse_args()
    build = PACKAGE.parents[1] / "build"
    build.mkdir(exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix="segmenter-consumer-", dir=build))
    if args.local_release:
        with release_server(args.local_release.resolve()) as (urls, requests):
            verify(root, urls)
            if not requests or any(path != "/" + NAME for path in requests):
                raise RuntimeError(f"Unexpected candidate downloads: {requests}")
            print(f"Verified {len(requests)} unauthenticated downloads.", flush=True)
    else:
        verify(root)


if __name__ == "__main__":
    main()
