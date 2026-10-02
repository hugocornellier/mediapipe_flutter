"""Prepare Google's official MediaPipe 1.0.0 macOS arm64 engine.

mediapipe_core bundles this library as the one MediaPipe engine every
task family binds on macOS (its `tasksRuntimeReleases` row pins the archive).

The runtime comes from the checksum-pinned wheel used by the independent CPU
and GPU reference generators.  This tool extracts only the native library and
its upstream notices.  It corrects Google's stale LC_ID_DYLIB, shortens
equivalent system-framework paths to leave Flutter's install-name capacity,
applies an ad-hoc signature, and verifies that code, data, sections and fixups
are unchanged.  The pinned identity is the unsigned image (everything before
the signature blob, with the two sizes codesign rewrites masked), so a new
Xcode changes the recorded file hash but not the pin.  With --release, it also
writes the deterministic archive published as the pinned download.  Nothing is
uploaded by this tool.
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

from cpu_reference import MACOS_WHEEL
from macho_metadata import rewrite_install_name, unsigned_sha256

PACKAGE = Path(__file__).resolve().parents[1]
REPO = PACKAGE.parents[1]
VERSION = '1.0.0'
WHEEL_URL, WHEEL_SHA256, UPSTREAM_LIBRARY_SHA256, _ = MACOS_WHEEL
UPSTREAM_LIBRARY = 'mediapipe/tasks/c/libmediapipe.dylib'
LIBRARY_NAME = 'libmediapipe.dylib'
INSTALL_NAME = '@rpath/libmediapipe.dylib'
ORIGINAL_INSTALL_NAME = '@rpath/libmediapipe_source.so'
# Unsigned-image digest of the prepared library; see macho_metadata.unsigned_sha256.
# The signed file's digest depends on the Xcode that signed it and is only
# recorded in the manifest.
UNSIGNED_SHA256 = 'b4c9e10a77fabea6ecbd88f93686ee9414c01762531eb3d487240958b2327fdc'
MINIMUM_OS = '14.0'
RELEASE_TAG = 'macos-tasks-runtime-v1.0.0'
ARCHIVE_NAME = 'mediapipe-tasks-runtime-1.0.0-macos-arm64.tar.gz'
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
    if unsigned_sha256(prepared) != UNSIGNED_SHA256:
        raise ValueError('Prepared library unsigned-image checksum mismatch')
    files[LIBRARY_NAME] = prepared
    toolchain = subprocess.check_output(
        ['xcodebuild', '-version'], text=True).splitlines()[0]
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
        'sha256': digest(prepared),
        'unsigned_sha256': UNSIGNED_SHA256,
        'signing_toolchain': toolchain,
        'files': {name: digest(data) for name, data in sorted(files.items())},
        'packaging': packaging,
        # Kept as published: the archive must stay byte-for-byte reproducible.
        'scope': ("Google's MediaPipe engine for macOS arm64, which "
                  'mediapipe_core bundles for every task family when an app '
                  'sets tasks_runtime: true.'),
    }
    files['manifest.json'] = (json.dumps(manifest, indent=2) + '\n').encode()
    for name, data in files.items():
        (output / name).write_bytes(data)
    check_library(library)
    print(json.dumps({'output': str(output), 'manifest': manifest}, indent=2))
    return files


def package(files, destination):
    """Write the published archive: exactly the files the hook accepts."""
    destination.mkdir(parents=True, exist_ok=True)
    archive = destination / ARCHIVE_NAME
    # Identical input bytes yield an identical archive, independent of local
    # filenames, timestamps, filesystem permissions, and Unix account names.
    with archive.open('wb') as raw:
        with gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode='w',
                              format=tarfile.USTAR_FORMAT) as bundle:
                for name, content in sorted(files.items()):
                    member = tarfile.TarInfo(name)
                    member.size = len(content)
                    member.mode = 0o644
                    bundle.addfile(member, io.BytesIO(content))
    archive_sha = digest(archive.read_bytes())
    (destination / 'SHA256SUMS').write_text(f'{archive_sha}  {ARCHIVE_NAME}\n')
    (destination / 'manifest.json').write_bytes(files['manifest.json'])
    (destination / 'RELEASE_NOTES.md').write_text(f"""Google's official MediaPipe {VERSION} macOS arm64 runtime, unmodified in code.

The library is `{UPSTREAM_LIBRARY}` from the official PyPI wheel
(`{WHEEL_URL.rsplit('/', 1)[-1]}`, SHA-256 `{WHEEL_SHA256}`). Only its
Mach-O metadata changes: `LC_ID_DYLIB` is corrected to `{INSTALL_NAME}`,
equivalent system-framework load paths are shortened, and the library carries
an ad-hoc signature. `manifest.json` records each change and proves the code,
data, sections and fixups are unchanged. The Flutter package pins the unsigned
image, so the signature can be replaced without changing the pin.

mediapipe_core bundles it on macOS arm64 when an app sets
`tasks_runtime: true`; every task family runs on it.
The archive includes Google's LICENSE and NOTICE from the wheel.

- Archive SHA-256: `{archive_sha}`
- Unsigned-image SHA-256: `{UNSIGNED_SHA256}`
- Library size: {len(files[LIBRARY_NAME]):,} bytes
""")
    print(json.dumps({'tag': RELEASE_TAG, 'archive': str(archive),
                      'sha256': archive_sha}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wheel', type=Path,
                        help='Already-downloaded checksum-pinned wheel')
    parser.add_argument('--output', type=Path,
                        default=PACKAGE / 'build/native/macos-tasks-runtime',
                        help='Prepared runtime directory')
    parser.add_argument('--release', type=Path,
                        help=f'Also write the {RELEASE_TAG} archive to this directory')
    args = parser.parse_args()
    wheel = fetch_wheel(
        args.wheel or REPO / 'build/wheels' / WHEEL_URL.rsplit('/', 1)[-1])
    files = prepare(wheel, args.output)
    if args.release:
        package(files, args.release)


if __name__ == '__main__':
    main()
