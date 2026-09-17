"""Package deterministic iOS CPU development archives and validation receipts.

No build or upload is performed. Simulator packaging requires a passing test
report for the exact library bytes. The device archive explicitly records that
physical-device inference has not been validated.
"""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import tarfile

from build_native import PACKAGE, REVISION, OPENCV_REVISION

TAG = 'vision-ios-v1.0.0-1'
LIBRARY = 'libmediapipe.dylib'


def prepare(directory, output, sdk, validation=None):
    library = (directory / LIBRARY).read_bytes()
    manifest = json.loads((directory / 'manifest.json').read_text())
    library_sha = hashlib.sha256(library).hexdigest()
    if (manifest.get('revision') != REVISION or
            manifest.get('opencv_revision') != OPENCV_REVISION or
            manifest.get('platform') != 'ios' or
            manifest.get('architecture') != 'arm64' or
            manifest.get('ios_sdk') != sdk or
            manifest.get('delegates') != ['cpu'] or
            manifest.get('sha256') != library_sha or
            manifest.get('bytes') != len(library) or not manifest.get('tasks')):
        raise ValueError('iOS artifact provenance/hash mismatch')
    if sdk == 'iphonesimulator':
        if validation is None:
            raise ValueError('A simulator validation report is required')
        report = json.loads(validation.read_text())
        if report.get('status') == 'passed':
            tested_sha = report.get('library_sha256')
            if report.get('experimental_support_override'):
                raise ValueError('Use a report without experimental support overrides')
        elif report.get('exit_code') == 0:
            tested_sha = report.get('libraries', {}).get('combined', {}).get('sha256')
        else:
            raise ValueError('Simulator validation did not pass')
        if tested_sha != library_sha:
            raise ValueError('Simulator validation used different library bytes')
        manifest['validated_tasks'] = ['face_detector', 'face_landmarker']
        manifest['validation'] = 'Flutter simulator CPU IMAGE/VIDEO reference and lifecycle tests passed.'
    else:
        manifest['validated_tasks'] = []
        manifest['validation'] = 'Build checks only; physical-device inference has not been validated.'
    manifest['release'] = TAG
    manifest['opencv_configuration'] = [
        flag for flag in manifest['opencv_configuration']
        if not flag.startswith('-DCMAKE_INSTALL_PREFIX=')]
    files = {LIBRARY: library,
             'manifest.json': (json.dumps(manifest, indent=2) + '\n').encode()}
    for name in ['LICENSE', 'NOTICE', 'opencv-licenses/LICENSE',
                 'opencv-licenses/CAROTENE_NOTICES']:
        if not (directory / name).is_file() or not (directory / name).stat().st_size:
            raise ValueError(f'Missing required notice: {name}')
    for path in sorted(directory.glob('opencv-licenses/*')):
        if not path.is_file() or path.is_symlink():
            raise ValueError(f'Unexpected notice entry: {path}')
        files[path.relative_to(directory).as_posix()] = path.read_bytes()
    for name in ['LICENSE', 'NOTICE']:
        files[name] = (directory / name).read_bytes()
    target = 'ios-simulator' if sdk == 'iphonesimulator' else 'ios'
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f'mediapipe-vision-1.0.0-{target}-arm64.tar.gz'
    with archive.open('wb') as raw:
        with gzip.GzipFile(filename='', fileobj=raw, mode='wb', mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode='w', format=tarfile.USTAR_FORMAT) as bundle:
                for name, content in sorted(files.items()):
                    member = tarfile.TarInfo(name)
                    member.size = len(content)
                    member.mode = 0o644
                    bundle.addfile(member, io.BytesIO(content))
    (output / f'manifest-{target}-arm64.json').write_bytes(files['manifest.json'])
    return {'archive': archive.name, 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
            'library_sha256': library_sha, 'sdk': sdk, 'bytes': len(library),
            'validated_tasks': manifest['validated_tasks']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator-report', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=PACKAGE / 'build/releases' / TAG)
    args = parser.parse_args()
    receipts = [prepare(PACKAGE / 'build/native/ios-simulator/arm64', args.output,
                        'iphonesimulator', args.simulator_report),
                prepare(PACKAGE / 'build/native/ios/arm64', args.output, 'iphoneos')]
    (args.output / 'SHA256SUMS').write_text(''.join(
        f"{row['sha256']}  {row['archive']}\n" for row in receipts))
    (args.output / 'release.json').write_text(json.dumps(receipts, indent=2) + '\n')
    (args.output / 'RELEASE_NOTES.md').write_text('''Combined MediaPipe v1.0.0 CPU development runtimes for iOS arm64.

The simulator slice has passed Flutter Face Detector and Face Landmarker
IMAGE/VIDEO reference comparisons, error recovery, pixel formats and queued
disposal. Only these two tasks are declared supported on the simulator.

The device slice is build-checked only. Physical iPhone inference, GPU,
camera use and device performance have not been validated. The Flutter package
does not declare physical-device support from these build checks.

Both slices are built from pinned upstream MediaPipe and OpenCV sources,
with compiler flags and hashes recorded in each manifest. Other task entry
points are exported but export checks alone do not establish inference support.
The archives include all required licenses and notices; models are separate.
''')
    print(json.dumps({'tag': TAG, 'output': str(args.output), 'artifacts': receipts}, indent=2))


if __name__ == '__main__':
    main()
