"""Generate official CPU references on the host that runs the Dart tests.

The checked-in goldens come from one physical macOS arm64 machine. The official
wheel's own results drift between hosts, so every job that compares a native
runtime against them regenerates the reference with the checksum-pinned wheel
for its own host and records how far the checked-in goldens sit from it. Nothing
here changes goldens, models, graphs or test tolerances.
"""
import argparse
import json
from pathlib import Path
import platform
import re
import sys

from prepare_gpu_reference import difference
from test_desktop import PACKAGE, REPO, dart_strings, digest, run

FACE_TASKS = [('face_detector', 'face_detection'),
              ('face_landmarker', 'face_landmarker')]
FACE_FILES = ['face_detection/official_reference.json',
              'face_detection/official_video_reference.json',
              'face_landmarker/official_reference.json']

# The macOS wheel has no consumer download row because macOS consumers use the
# published native archives. The GPU oracle already pins it for this same use.
MACOS_WHEEL = (
    'https://files.pythonhosted.org/packages/42/d7/'
    '3a5dfaa86128db110c62a4d0f0c948304817932c9dd3257313bbdf24f7d5/'
    'mediapipe-1.0.0-py3-none-macosx_11_0_arm64.whl',
    '7ee4783be41b2de345e1eb71e2f7e7c159a50ed5c283e60ccb8f5a6027c70a82',
    'aa1314b6cc3eb2ce3b610808433930c016e19cdc0f62cbb3f10cc7e912b6f72f',
    '1.0.0',
)


def host_target():
    """The pinned wheel target matching this host, or None when unsupported."""
    system = platform.system()
    machine = platform.machine().lower()
    if system == 'Darwin' and machine == 'arm64':
        return 'macos/arm64'
    if machine in ('amd64', 'x86_64'):
        return {'Linux': 'linux/x64', 'Windows': 'windows/x64'}.get(system)
    return None


def wheel_pin(target):
    """Returns the pinned wheel URL, wheel and native library digests, and version."""
    if target == 'macos/arm64':
        return MACOS_WHEEL
    pins = (PACKAGE / 'sdk_downloads.dart').read_text()
    row = re.search(r"'" + target + r"': VisionWheelRelease\((.*?)\n  \),",
                    pins, re.S).group(1)
    return (dart_strings(re.search(r'url:(.*?),', row, re.S).group(1)),
            re.search(r"sha256:\s*'([a-f0-9]+)'", row).group(1),
            re.search(r"librarySha256:\s*'([a-f0-9]+)'", row).group(1),
            re.search(r"version:\s*'([0-9.]+)'", row).group(1))


def install(root, target):
    """Creates an isolated environment holding only the pinned official wheel."""
    wheel_url, wheel_sha, _, _ = wheel_pin(target)
    environment = root / 'python'
    run([sys.executable, '-m', 'venv', environment], REPO, root / 'venv.log')
    python = environment / ('Scripts/python.exe' if platform.system() == 'Windows'
                            else 'bin/python')
    run([python, '-m', 'pip', 'install', '--disable-pip-version-check',
         wheel_url + '#sha256=' + wheel_sha], REPO, root / 'pip.log')
    return python


def generate(root, output, target, tasks=FACE_TASKS, files=FACE_FILES,
             python=None, env=None):
    """Writes references and a provenance receipt for `target` into `output`."""
    wheel_url, wheel_sha, library_sha, version = wheel_pin(target)
    root.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    if python is None:
        python = install(root, target)
    for task, folder in tasks:
        run([python, '-u', '-X', 'faulthandler', '-B',
             PACKAGE / f'tool/generate_{task}_reference.py',
             '--output-dir', output / folder], REPO,
            root / f'{task}-reference.log', env=env)
    comparisons = {}
    for name in files:
        reference = json.loads((output / name).read_text())
        if reference['library_sha256'] != library_sha:
            raise RuntimeError('Independent reference used a different native library')
        comparisons[name] = difference(
            json.loads((PACKAGE / 'test/fixtures' / name).read_text()), reference)
    provenance = {
        'runtime': 'mediapipe==' + version, 'source': 'official-python-api',
        'delegate': 'CPU', 'target': target,
        'library_sha256': library_sha, 'wheel_sha256': wheel_sha,
        'files': {name: digest(output / name) for name in files},
        'checked_in_reference_differences': comparisons,
    }
    (output / 'provenance.json').write_text(json.dumps(provenance, indent=2))
    return {'python': python, 'wheel_url': wheel_url, 'wheel_sha256': wheel_sha,
            'library_sha256': library_sha, 'comparisons': comparisons,
            'provenance': provenance}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--target', help='Defaults to this host')
    args = parser.parse_args()
    target = args.target or host_target()
    if target is None:
        raise SystemExit('No official CPU wheel is pinned for this host.')
    output = args.output_dir.resolve()
    result = generate(output, output, target)
    print(json.dumps(result['comparisons'], indent=2), flush=True)
    print(f'Verified official {target} CPU references: {output}', flush=True)


if __name__ == '__main__':
    main()
