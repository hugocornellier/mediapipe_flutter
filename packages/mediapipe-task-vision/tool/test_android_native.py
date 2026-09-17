"""Run face C ABI/inference smoke checks on an arm64 Android test device.

This checks native loading and basic inference, not Flutter packaging, numerical
reference parity, video/lifecycle behavior or physical-device performance.
"""
import argparse
import json
from pathlib import Path
import platform
import re
import subprocess
import tempfile
import time

from build_native import PACKAGE, REPO, REVISION
from build_android import NDK_VERSION
from test_desktop import digest, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ndk', required=True, type=Path)
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--device', required=True)
    parser.add_argument('--require-page-size', type=int)
    parser.add_argument('--source-dir', type=Path,
                        default=REPO / 'build/codex-tmp/mediapipe-android')
    args = parser.parse_args()
    adb = [args.adb, '-s', args.device]
    source = args.source_dir.resolve()
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source,
                                       text=True).strip()
    if revision != REVISION:
        raise SystemExit('Refusing an unpinned source checkout.')
    artifact = PACKAGE / 'build/native/android/arm64-v8a'
    manifest = json.loads((artifact / 'manifest.json').read_text())
    ndk = args.ndk.resolve()
    version = re.search(r'^Pkg.Revision\s*=\s*(\S+)\s*$',
                        (ndk / 'source.properties').read_text(), re.MULTILINE)
    if (version is None or version.group(1) != NDK_VERSION or
            manifest.get('revision') != REVISION or
            manifest.get('abi') != 'arm64-v8a' or
            manifest.get('ndk_version') != NDK_VERSION):
        raise SystemExit('Refusing an unpinned Android artifact or compiler.')
    libraries = {'libmediapipe.so': manifest['sha256'], **manifest['dependencies']}
    for name, expected in libraries.items():
        if digest(artifact / name) != expected:
            raise SystemExit(f'Artifact hash mismatch: {name}')
    root = Path(tempfile.mkdtemp(prefix='android-native-', dir=REPO / 'build/codex-tmp'))
    report = {'target': 'android/arm64', 'device': args.device,
              'revision': revision, 'ndk_version': NDK_VERSION,
              'libraries': libraries, 'status': 'running',
              'scope': 'Native face IMAGE ABI/count smoke only; Flutter/reference tests still required.'}
    report_path = root / 'report.json'
    try:
        deadline = time.monotonic() + 180
        while subprocess.check_output([*adb, 'shell', 'getprop', 'sys.boot_completed'],
                                      text=True).strip() != '1':
            if time.monotonic() > deadline:
                raise TimeoutError('Android device did not finish booting')
            time.sleep(1)
        for prop in ['ro.product.cpu.abi', 'ro.build.version.sdk', 'ro.kernel.qemu']:
            report[prop] = subprocess.check_output([*adb, 'shell', 'getprop', prop],
                                                  text=True).strip()
        if report['ro.product.cpu.abi'] != 'arm64-v8a':
            raise RuntimeError('This smoke runner requires an arm64 Android device')
        page_size = int(subprocess.check_output([*adb, 'shell', 'getconf', 'PAGE_SIZE'], text=True))
        report['page_size'] = page_size
        if args.require_page_size and page_size != args.require_page_size:
            raise RuntimeError(f'Expected page size {args.require_page_size}, got {page_size}')
        host = 'darwin-x86_64' if platform.system() == 'Darwin' else 'linux-x86_64'
        clang = ndk / f'toolchains/llvm/prebuilt/{host}/bin/clang++'
        executables = []
        for name in ['native_smoke', 'native_landmarker_smoke']:
            executable = root / name
            run([clang, '--target=aarch64-linux-android24', '-std=c++17', '-O2',
                 '-I', source, PACKAGE / f'tool/{name}.cc', '-L', artifact,
                 '-lmediapipe', '-Wl,--allow-shlib-undefined',
                 '-Wl,-z,max-page-size=16384', '-o', executable], REPO, root / f'{name}-build.log')
            executables.append(executable)
        remote = '/data/local/tmp/' + root.name
        run([*adb, 'shell', 'mkdir', remote], REPO, root / 'mkdir.log')
        files = [*(artifact / name for name in libraries), *executables,
                 PACKAGE / 'models/blaze_face_short_range.tflite',
                 PACKAGE / 'models/face_landmarker.task',
                 PACKAGE / 'test/fixtures/face_detection/landmark-ex1.jpg']
        report['inputs'] = {path.name: digest(path) for path in files[-3:]}
        for index, path in enumerate(files):
            run([*adb, 'push', path, remote + '/' + path.name], REPO, root / f'push-{index}.log')
        for executable, model in zip(executables, ['blaze_face_short_range.tflite', 'face_landmarker.task']):
            run([*adb, 'shell', 'chmod', '755', remote + '/' + executable.name],
                REPO, root / f'{executable.name}-chmod.log')
            run([*adb, 'shell', 'env', 'LD_LIBRARY_PATH=' + remote,
                 remote + '/' + executable.name, remote + '/' + model,
                 remote + '/landmark-ex1.jpg', 'cpu'], REPO,
                root / f'{executable.name}-inference.log', timeout=180)
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
