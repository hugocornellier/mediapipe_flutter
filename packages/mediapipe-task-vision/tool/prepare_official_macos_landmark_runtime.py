"""Prepare Google's official MediaPipe 1.0.0 macOS arm64 landmark runtime.

The runtime comes from the checksum-pinned wheel used by the independent CPU
and GPU reference generators.  This tool extracts only the native library and
its upstream notices.  It corrects Google's stale LC_ID_DYLIB, shortens
equivalent system-framework paths to leave Flutter's install-name capacity,
applies an ad-hoc signature, and verifies that code, data, sections and fixups
are unchanged.  Nothing is published by this tool.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import urllib.request
import zipfile

from cpu_reference import MACOS_WHEEL
from macho_metadata import rewrite_install_name

PACKAGE = Path(__file__).resolve().parents[1]
REPO = PACKAGE.parents[1]
VERSION = '1.0.0'
WHEEL_URL, WHEEL_SHA256, UPSTREAM_LIBRARY_SHA256 = MACOS_WHEEL
UPSTREAM_LIBRARY = 'mediapipe/tasks/c/libmediapipe.dylib'
LIBRARY_NAME = 'libmediapipe.dylib'
INSTALL_NAME = '@rpath/libmediapipe.dylib'
ORIGINAL_INSTALL_NAME = '@rpath/libmediapipe_source.so'
ARTIFACT_SHA256 = '41e98323ac91465270d0ae6348e9bf7d8fd9b3973521838f44ee1d61271607f9'
MINIMUM_OS = '14.0'
NOTICE_SHA256 = {
    'LICENSE': '8707eef0533987efc5b155d64761eeb6e20793f50b9bd1a68dad1cf4719d0ed8',
    'NOTICE': 'd3b4a80a24a01fd445d4b70a610fd836ec3547c3a62eb835a1041956c38d9f56',
}
REQUIRED_SYMBOLS = (
    'MpFaceLandmarkerCreate', 'MpFaceLandmarkerDetectForVideo',
    'MpHandLandmarkerCreate', 'MpHandLandmarkerDetectForVideo',
    'MpPoseLandmarkerCreate', 'MpPoseLandmarkerDetectForVideo',
)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def fetch_wheel(destination):
    if destination.exists() and digest(destination.read_bytes()) == WHEEL_SHA256:
        return destination
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(WHEEL_URL, timeout=300) as response:
        data = response.read()
    if digest(data) != WHEEL_SHA256:
        raise ValueError('Official wheel checksum mismatch')
    destination.write_bytes(data)
    return destination


def check_library(library):
    build = subprocess.check_output(
        ['xcrun', 'vtool', '-show-build', str(library)], text=True)
    architecture = subprocess.check_output(
        ['xcrun', 'lipo', '-archs', str(library)], text=True).strip()
    if (architecture != 'arm64' or 'platform MACOS' not in build or
            not re.search(rf'^\s*minos {re.escape(MINIMUM_OS)}\s*$',
                          build, re.MULTILINE)):
        raise ValueError(f'Expected a macOS arm64 library requiring {MINIMUM_OS}')
    identity = subprocess.check_output(
        ['otool', '-D', str(library)], text=True).splitlines()
    if identity[-1].strip() != INSTALL_NAME:
        raise ValueError('Prepared library has the wrong LC_ID_DYLIB')
    dependencies = subprocess.check_output(
        ['otool', '-L', str(library)], text=True).splitlines()
    for line in dependencies[2:]:
        if not line.strip().startswith(('/usr/lib/', '/System/Library/')):
            raise ValueError(f'Non-system dependency: {line}')
    symbols = {name.removeprefix('_') for name in subprocess.check_output(
        ['nm', '-gjU', str(library)], text=True).splitlines()}
    for symbol in REQUIRED_SYMBOLS:
        if symbol not in symbols:
            raise ValueError(f'Missing native symbol: {symbol}')
    subprocess.run(['codesign', '--verify', '--strict', str(library)], check=True)


def prepare(wheel, output):
    wheel_bytes = wheel.read_bytes()
    if digest(wheel_bytes) != WHEEL_SHA256:
        raise ValueError('Official wheel checksum mismatch')
    with zipfile.ZipFile(wheel) as source:
        original = source.read(UPSTREAM_LIBRARY)
        files = {
            'LICENSE': source.read(
                f'mediapipe-{VERSION}.dist-info/licenses/LICENSE'),
            'NOTICE': source.read(
                f'mediapipe-{VERSION}.dist-info/licenses/NOTICE'),
        }
    if digest(original) != UPSTREAM_LIBRARY_SHA256:
        raise ValueError('Official library checksum mismatch')
    for name, expected in NOTICE_SHA256.items():
        if digest(files[name]) != expected:
            raise ValueError(f'Official {name} checksum mismatch')

    output.mkdir(parents=True, exist_ok=True)
    library = output / LIBRARY_NAME
    library.write_bytes(original)
    packaging = rewrite_install_name(library, INSTALL_NAME)
    if packaging['original_install_name'] != ORIGINAL_INSTALL_NAME:
        raise ValueError('Official library install name changed upstream')
    prepared = library.read_bytes()
    if digest(prepared) != ARTIFACT_SHA256:
        raise ValueError('Prepared library checksum mismatch')
    files[LIBRARY_NAME] = prepared
    manifest = {
        'origin': 'official-pypi-wheel',
        'upstream_version': VERSION,
        'upstream_url': WHEEL_URL,
        'upstream_sha256': WHEEL_SHA256,
        'upstream_library': UPSTREAM_LIBRARY,
        'upstream_library_sha256': UPSTREAM_LIBRARY_SHA256,
        'platform': 'macos',
        'architecture': 'arm64',
        'minimum_os': MINIMUM_OS,
        'delegates': ['cpu', 'gpu'],
        'bytes': len(prepared),
        'sha256': ARTIFACT_SHA256,
        'files': {name: digest(data) for name, data in sorted(files.items())},
        'packaging': packaging,
        'scope': ('Official runtime selected only for the gallery Live Face Landmarker, '
                  'Live Hand Landmarker and Live Pose Landmarker.'),
    }
    files['manifest.json'] = (json.dumps(manifest, indent=2) + '\n').encode()
    for name, data in files.items():
        (output / name).write_bytes(data)
    check_library(library)
    print(json.dumps({'output': str(output), 'manifest': manifest}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wheel', type=Path,
                        help='Already-downloaded checksum-pinned wheel')
    parser.add_argument('--output', type=Path,
                        default=PACKAGE / 'build/native/official-macos-landmarks',
                        help='Prepared runtime directory')
    args = parser.parse_args()
    wheel = fetch_wheel(
        args.wheel or REPO / 'build/wheels' / WHEEL_URL.rsplit('/', 1)[-1])
    prepare(wheel, args.output)


if __name__ == '__main__':
    main()
