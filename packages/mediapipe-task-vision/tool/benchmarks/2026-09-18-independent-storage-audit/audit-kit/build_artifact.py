#!/usr/bin/env python3
"""Build one labelled release artifact from an isolated tree and retain it with a receipt.

  build_artifact.py --tree <tree> --platform ios|macos --label base|m0|m1|m2|m3
                    [--mode N] --out <apps dir>

--mode adds --dart-define=MEDIAPIPE_IOS_IMAGE_STORAGE=N. Without it the library
default applies (mode 2 in the candidate, nothing in the baseline). Receipts
hash sources, signed binaries, unsigned binaries (signature removed from a
copy) and the bundled fixtures/model, so later runs can prove the artifact is
unchanged and that equal code produced equal machine code.
"""
import argparse, datetime, hashlib, json, pathlib, shutil, subprocess, tempfile

SOURCES = [
    'packages/mediapipe-task-vision/native/ios/face_sdk_bridge.mm',
    'packages/mediapipe-task-vision/lib/src/io/native_ios_sdk.dart',
    'packages/mediapipe-task-vision/lib/src/io/native_face_landmarker.dart',
    'packages/mediapipe-task-vision/lib/src/io/face_landmarker.dart',
    'packages/mediapipe-task-vision/lib/src/interface/vision_types.dart',
    'gallery/tool/storage_audit_benchmark.dart',
    'gallery/ios/Runner/AppDelegate.swift',
    'gallery/macos/Runner/MainFlutterWindow.swift',
    'gallery/pubspec.yaml',
]


def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def unsigned_sha(path):
    with tempfile.TemporaryDirectory() as tmp:
        copy = pathlib.Path(tmp) / 'bin'
        shutil.copyfile(path, copy)
        subprocess.run(['codesign', '--remove-signature', str(copy)], check=True)
        return sha(copy)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--tree', type=pathlib.Path, required=True)
    p.add_argument('--platform', choices=['ios', 'macos'], required=True)
    p.add_argument('--label', required=True)
    p.add_argument('--mode', type=int)
    p.add_argument('--out', type=pathlib.Path, required=True)
    a = p.parse_args()
    gallery = a.tree / 'gallery'
    dest = a.out / a.label
    if dest.exists():
        raise SystemExit(f'refusing to overwrite {dest}')
    command = ['flutter', 'build', a.platform, '--release',
               '-t', 'tool/storage_audit_benchmark.dart',
               f'--dart-define=BENCH_ARTIFACT={a.label}']
    if a.mode is not None:
        command.append(f'--dart-define=MEDIAPIPE_IOS_IMAGE_STORAGE={a.mode}')
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    log = a.out / f'{a.label}-build.log'
    a.out.mkdir(parents=True, exist_ok=True)
    with open(log, 'w') as f:
        result = subprocess.run(command, cwd=gallery, stdout=f, stderr=subprocess.STDOUT)
    if result.returncode:
        raise SystemExit(f'build failed, see {log}')
    if a.platform == 'ios':
        app = gallery / 'build/ios/iphoneos/Runner.app'
        binaries = {'App': 'Frameworks/App.framework/App',
                    'mediapipe_ios': 'Frameworks/mediapipe_ios.framework/mediapipe_ios',
                    'Flutter': 'Frameworks/Flutter.framework/Flutter',
                    'Runner': 'Runner'}
        assets = 'Frameworks/App.framework/flutter_assets'
    else:
        app = gallery / 'build/macos/Build/Products/Release/mediapipe_gallery.app'
        binaries = {'App': 'Contents/Frameworks/App.framework/Versions/A/App',
                    'FlutterMacOS': 'Contents/Frameworks/FlutterMacOS.framework/Versions/A/FlutterMacOS',
                    'Runner': 'Contents/MacOS/mediapipe_gallery'}
        for lib in sorted((app / 'Contents/Frameworks').glob('*.framework')):
            name = lib.name.removesuffix('.framework')
            if name not in ('App', 'FlutterMacOS'):
                binaries[name] = f'Contents/Frameworks/{lib.name}/Versions/A/{name}'
        assets = 'Contents/Frameworks/App.framework/Resources/flutter_assets'
    dest.mkdir(parents=True)
    retained = dest / app.name
    subprocess.run(['cp', '-cR', str(app), str(retained)], check=True)
    receipt = {
        'label': a.label, 'platform': a.platform, 'command': command,
        'mode_define': a.mode, 'tree': str(a.tree), 'build_started_at': started,
        'build_finished_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'flutter': subprocess.run(['flutter', '--version', '--machine'], capture_output=True, text=True).stdout,
        'xcode': subprocess.run(['xcodebuild', '-version'], capture_output=True, text=True).stdout.strip(),
        'sources': {s: sha(a.tree / s) for s in SOURCES if (a.tree / s).exists()},
        'binaries': {}, 'unsigned': {}, 'bundled': {},
    }
    for key, rel in binaries.items():
        path = retained / rel
        if path.exists():
            receipt['binaries'][key] = sha(path)
            receipt['unsigned'][key] = unsigned_sha(path)
    for rel in ['assets/bench/portrait_480x640_bgra.bin',
                'assets/bench/portrait_1080x1920_bgra.bin',
                'assets/models/face_landmarker.task']:
        receipt['bundled'][rel] = sha(retained / assets / rel)
    (dest / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({k: receipt[k] for k in ('label', 'command', 'binaries', 'unsigned')}, indent=2))


if __name__ == '__main__':
    main()
