"""Prepare an unchanged official macOS runtime for Interactive Segmenter.

The new stateful implementation is present in Google's Python wheel but is not
available as a standalone public C++ build target. No Python is shipped to apps.
This tool verifies the wheel and extracts only its native library and notices.
It creates a deterministic, reviewable archive; it never publishes anything.
"""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile
import urllib.request
import zipfile

PACKAGE = Path(__file__).resolve().parents[1]
REPO = PACKAGE.parents[1]
VERSION = '1.0.1'
TAG = 'interactive-segmenter-v1.0.1-1'
WHEEL_URL = ('https://files.pythonhosted.org/packages/18/56/'
             '911762884caba685dc8156d0136c58196a228c2b447023cfa0cfdb32f6c5/'
             'mediapipe-1.0.1-py3-none-macosx_11_0_arm64.whl')
WHEEL_SHA256 = '0a9fb67957f7d28e84f485e9c6716a43367b3f6f07170f31c3f72cac1addd031'
LIBRARY_SHA256 = '9cffc37134d98bdbbcc4b5811d2e2acd66361d05b89761e68a5cb72e0406b53a'
MODEL_URL = ('https://storage.googleapis.com/mediapipe-models/'
             'interactive_segmenter_v2/magic_touch/int8/1/interactive_segmentation.task')
MODEL_SHA256 = '38431bc66b883404e8397f74c3579404315b9b52b04a46c6346fe906a7309b03'
LIBRARY_NAME = 'libinteractive_segmenter.dylib'
ARCHIVE_NAME = 'mediapipe-interactive-segmenter-1.0.1-macos-arm64.tar.gz'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def prepare(wheel, output):
    if digest(wheel.read_bytes()) != WHEEL_SHA256:
        raise ValueError('Official wheel checksum mismatch')
    with zipfile.ZipFile(wheel) as source:
        files = {
            LIBRARY_NAME: source.read('mediapipe/tasks/c/libmediapipe.dylib'),
            'LICENSE': source.read('mediapipe-1.0.1.dist-info/licenses/LICENSE'),
            'NOTICE': source.read('mediapipe-1.0.1.dist-info/licenses/NOTICE'),
        }
    if digest(files[LIBRARY_NAME]) != LIBRARY_SHA256:
        raise ValueError('Official library checksum mismatch')
    manifest = {
        'origin': 'official-pypi-wheel', 'upstream_version': VERSION,
        'upstream_url': WHEEL_URL, 'upstream_sha256': WHEEL_SHA256,
        'upstream_library': 'mediapipe/tasks/c/libmediapipe.dylib',
        'release': TAG, 'platform': 'macos', 'architecture': 'arm64',
        'minimum_os': '14.0', 'delegates': ['cpu'],
        'sha256': LIBRARY_SHA256, 'bytes': len(files[LIBRARY_NAME]),
        'files': {name: digest(data) for name, data in files.items()},
        'modifications': 'None; native bytes and upstream notices are unchanged.',
        'scope': 'Full upstream runtime, exposed here only for Interactive Segmenter. '
                 'GPU is not enabled: the upstream macOS stroke shader fails to initialize.',
    }
    files['manifest.json'] = (json.dumps(manifest, indent=2) + '\n').encode()
    output.mkdir(parents=True, exist_ok=True)
    for name, data in files.items():
        (output / name).write_bytes(data)
    library = output / LIBRARY_NAME
    build = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(library)], text=True)
    arch = subprocess.check_output(['xcrun', 'lipo', '-archs', str(library)], text=True).strip()
    if ('platform MACOS' not in build or arch != 'arm64' or
            not re.search(r'^\s*minos 14\.0\s*$', build, re.MULTILINE)):
        raise ValueError('Expected macOS ARM64 native library with minimum OS 14.0')
    symbols = set(subprocess.check_output(['nm', '-gjU', str(library)], text=True).splitlines())
    for name in ('MpInteractiveSegmenterCreate', 'MpInteractiveSegmenterSetImage',
                 'MpInteractiveSegmenterSegment', 'MpInteractiveSegmenterClose',
                 'MpImageCreateFromFile', 'MpImageCreateFromUint8Data',
                 'MpImageDataFloat32', 'MpImageGetWidth', 'MpImageGetHeight',
                 'MpImageGetChannels', 'MpImageGetByteDepth', 'MpImageFree', 'MpErrorFree'):
        if '_' + name not in symbols:
            raise ValueError(f'Missing native symbol: {name}')
    dependencies = subprocess.check_output(['otool', '-L', str(library)], text=True)
    for line in dependencies.splitlines()[2:]:
        if not line.strip().startswith(('/usr/lib/', '/System/Library/')):
            raise ValueError(f'Non-system dependency: {line}')
    release = PACKAGE / 'build/releases' / TAG
    release.mkdir(parents=True, exist_ok=True)
    archive = release / ARCHIVE_NAME
    with archive.open('wb') as raw:
        with gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode='w', format=tarfile.USTAR_FORMAT) as bundle:
                for name, data in sorted(files.items()):
                    entry = tarfile.TarInfo(name)
                    entry.size = len(data)
                    entry.mode = 0o644
                    bundle.addfile(entry, io.BytesIO(data))
    checksum = digest(archive.read_bytes())
    (release / 'manifest.json').write_bytes(files['manifest.json'])
    (release / 'SHA256SUMS').write_text(f'{checksum}  {ARCHIVE_NAME}\n')
    (release / 'RELEASE_NOTES.md').write_text(
        f'Interactive Segmenter runtime for macOS arm64, CPU only.\n\n'
        f'Unchanged native library from the official MediaPipe {VERSION} macOS wheel; '
        'includes its complete LICENSE and NOTICE. This is the full upstream runtime, '
        'not a standalone source build. Models are separate. No Python is required by apps.\n\n'
        f'Archive SHA-256: `{checksum}`\n\nLibrary SHA-256: `{LIBRARY_SHA256}`\n')
    print(json.dumps({'archive': str(archive), 'sha256': checksum,
                      'bytes': archive.stat().st_size, 'manifest': manifest}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wheel', type=Path)
    parser.add_argument('--output', type=Path,
                        default=PACKAGE / 'build/native/interactive_segmenter')
    args = parser.parse_args()
    wheel = args.wheel or REPO / 'build/codex-tmp/mediapipe-1.0.1-macos-arm64.whl'
    if not wheel.exists():
        wheel.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(WHEEL_URL, timeout=120) as response:
            data = response.read()
        if digest(data) != WHEEL_SHA256:
            raise ValueError('Downloaded wheel checksum mismatch')
        wheel.write_bytes(data)
    prepare(wheel, args.output)


if __name__ == '__main__':
    main()
