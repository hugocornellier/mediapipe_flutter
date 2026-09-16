"""Validate face CPU references and debug/release APKs on an Android emulator.

Uses a fresh consumer and a verified local runtime. This does not establish
physical-device, GPU or camera support, or validation of other vision tasks.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import time
import zipfile

from build_native import PACKAGE, REPO
from mobile_consumer import prepare_app
from test_desktop import digest, run


def elf_payload(data):
    # Gradle strips non-loaded debug/section metadata. Compare the actual
    # loadable code/data and program headers while ignoring the ELF header's
    # section-table pointers. Check type/architecture separately.
    if data[:6] != b'\x7fELF\x02\x01':
        raise ValueError('Expected little-endian ELF64')
    identity = struct.unpack_from('<HH', data, 16)
    offset = struct.unpack_from('<Q', data, 32)[0]
    stride, count = struct.unpack_from('<HH', data, 54)
    segments = []
    for index in range(count):
        header = struct.unpack_from('<IIQQQQQQ', data, offset + index * stride)
        kind, _, file_offset, _, _, size, _, _ = header
        if kind == 1:
            segments.append((header, data[max(64, file_offset):file_offset + size]))
    if not segments:
        raise ValueError('Missing ELF loadable segments')
    return identity, segments


def launch_apk(adb, app, apk, identifier, activity, marker, root, mode):
    run([*adb, 'install', '-r', apk], app, root / f'install-{mode}.log', timeout=180)
    log = root / f'inference-{mode}.log'
    with log.open('w') as output:
        process = subprocess.Popen([*adb, 'logcat', '-T', '1', '-v', 'brief',
                                    'flutter:I', 'AndroidRuntime:E', '*:S'],
                                   stdout=output, stderr=subprocess.STDOUT)
        try:
            run([*adb, 'shell', 'am', 'start', '-W', '-n', identifier + '/' + activity],
                app, root / f'launch-{mode}.log', timeout=120)
            deadline = time.monotonic() + 120
            while marker not in log.read_text(errors='replace'):
                if time.monotonic() >= deadline:
                    raise TimeoutError(f'Packaged {mode} app did not confirm CPU inference; see {log}')
                if process.poll() is not None:
                    raise RuntimeError('Android logcat stopped before confirming inference')
                time.sleep(0.5)
        finally:
            process.terminate()
            process.wait(timeout=10)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--device', required=True)
    parser.add_argument('--require-page-size', type=int)
    args = parser.parse_args()
    adb = [args.adb, '-s', args.device]
    abi = subprocess.check_output([*adb, 'shell', 'getprop', 'ro.product.cpu.abi'], text=True).strip()
    architecture = {'arm64-v8a': 'arm64', 'x86_64': 'x64'}.get(abi)
    if architecture is None:
        raise SystemExit('The face CI runtime requires arm64-v8a or x86_64 Android.')
    build = REPO / 'build/codex-tmp'
    build.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix='android-consumer-', dir=build))
    print(f'Validation artifacts: {root}', flush=True)
    report = {'target': 'android/' + architecture, 'device': args.device,
              'abi': abi, 'delegate': 'CPU', 'tasks': ['face_detector', 'face_landmarker'],
              'status': 'running', 'prebuilt': False}
    report_path = root / 'report.json'
    try:
        report['page_size'] = int(subprocess.check_output(
            [*adb, 'shell', 'getconf', 'PAGE_SIZE'], text=True))
        report['android_api'] = int(subprocess.check_output(
            [*adb, 'shell', 'getprop', 'ro.build.version.sdk'], text=True))
        if args.require_page_size and report['page_size'] != args.require_page_size:
            raise RuntimeError('Android emulator page size does not match the requested check')
        source = PACKAGE / ('build/native/android/' + abi)
        manifest = json.loads((source / 'manifest.json').read_text())
        hashes = {'libmediapipe.so': manifest['sha256'], **manifest['dependencies']}
        for name, expected in hashes.items():
            if digest(source / name) != expected:
                raise RuntimeError(f'Android runtime hash mismatch: {name}')
        report['libraries'] = hashes
        report['library_manifest'] = manifest
        app, vision = prepare_app(root, 'android', report['tasks'],
                                  ['face_detector', 'face_landmarker', 'pixel_conversion'],
                                  ['blaze_face_short_range.tflite', 'face_landmarker.task'])
        shutil.copytree(source, vision / ('build/native/android/' + abi))
        project = app / 'android/app/build.gradle.kts'
        content = project.read_text().replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
        content = content.replace('ndkVersion = flutter.ndkVersion', 'ndkVersion = "28.2.13676358"')
        identifier = 'com.example.mediapipe.android' + re.sub('[^a-z0-9]', '', root.name)
        content = re.sub(r'applicationId = "[^"]+"', 'applicationId = "' + identifier + '"', content)
        project.write_text(content)
        # Gradle's namespace still names MainActivity's original package; the
        # application ID is unique so these tests cannot replace another app.
        namespace = re.search(r'namespace = "([^"]+)"', content).group(1)
        activity = namespace + '.MainActivity'
        run(['flutter', 'pub', 'get'], app, root / 'pub.log')
        run(['flutter', 'test', '-d', args.device, 'integration_test/tasks_test.dart',
             '--reporter', 'expanded'], app, root / 'integration.log', timeout=2400)
        totals = re.findall(r'\+(\d+)(?: ~(\d+))?: All tests passed!',
                            (root / 'integration.log').read_text())
        if not totals:
            raise RuntimeError('Integration runner did not report passing test counts')
        passed, skipped = totals[-1]
        report['tests'] = {'passed': int(passed), 'skipped': int(skipped or 0)}
        report['apks'] = {}
        original_smoke = (app / 'lib/main.dart').read_text()
        platform = 'android-arm64' if abi == 'arm64-v8a' else 'android-x64'
        for mode in ['debug', 'release']:
            marker = root.name + '/' + mode + ': bundled cpu Face Detector and Face Landmarker inference passed.'
            smoke = original_smoke.replace('Flutter release: bundled', root.name + '/' + mode + ': bundled')
            (app / 'lib/main.dart').write_text(smoke)
            run(['flutter', 'build', 'apk', '--' + mode, '--target-platform=' + platform],
                app, root / f'build-{mode}.log', timeout=1800)
            apk = app / f'build/app/outputs/flutter-apk/app-{mode}.apk'
            bundled = {}
            payloads = {'libface_detector.so': 'libmediapipe.so',
                        'libface_landmarker.so': 'libmediapipe.so',
                        'libopencv_java4.so': 'libopencv_java4.so',
                        'libc++_shared.so': 'libc++_shared.so'}
            with zipfile.ZipFile(apk) as archive:
                for name, original in payloads.items():
                    data = archive.read('lib/' + abi + '/' + name)
                    if elf_payload(data) != elf_payload((source / original).read_bytes()):
                        raise RuntimeError(f'APK packaging changed loadable code/data: {name}')
                    bundled[name] = {'source_sha256': hashes[original],
                                     'bundled_sha256': hashlib.sha256(data).hexdigest(),
                                     'load_segments_unchanged': True}
            # Explicit fully qualified activity name remains valid after using
            # a unique application ID for this isolated consumer.
            launch_apk(adb, app, apk, identifier, activity, marker, root, mode)
            report['apks'][mode] = {'inference': 'passed', 'libraries': bundled}
        report['status'] = 'passed'
    except Exception as error:
        report['status'] = 'failed'
        report['error'] = str(error)
        raise
    finally:
        report_path.write_text(json.dumps(report, indent=2) + '\n')
        print(f'Report: {report_path}', flush=True)


if __name__ == '__main__':
    main()
