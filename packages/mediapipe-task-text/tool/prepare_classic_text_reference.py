"""Generate independent CPU text references on the host running the Dart tests.

Uses Google's checksum-pinned wheel; never rewrites the checked-in references or
changes test tolerances. Python is used only to prepare the test oracle, outside
the fresh consumer build where native build tools and Python remain blocked.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys

from generate_classic_text_reference import LIBRARY_SHA256, PACKAGE

REPO = PACKAGE.parents[1]
BASELINE = PACKAGE / 'test/fixtures/classic_text/official_reference.json'
WHEEL_URL = ('https://files.pythonhosted.org/packages/18/56/'
             '911762884caba685dc8156d0136c58196a228c2b447023cfa0cfdb32f6c5/'
             'mediapipe-1.0.1-py3-none-macosx_11_0_arm64.whl')
WHEEL_SHA256 = '0a9fb67957f7d28e84f485e9c6716a43367b3f6f07170f31c3f72cac1addd031'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def reference_file():
    """Select a verified host oracle, or the reviewed physical-Mac baseline."""
    directory = os.environ.get('MEDIAPIPE_CLASSIC_TEXT_REFERENCE_DIR')
    if directory is None:
        return BASELINE
    root = Path(directory)
    reference = root / 'official_reference.json'
    receipt = json.loads((root / 'provenance.json').read_text())
    current = json.loads(reference.read_text())
    baseline = json.loads(BASELINE.read_text())
    if (receipt.get('source') != 'official-python-api'
            or receipt.get('runtime') != 'mediapipe==1.0.1'
            or receipt.get('delegate') != 'CPU'
            or receipt.get('library_sha256') != LIBRARY_SHA256
            or receipt.get('wheel_sha256') != WHEEL_SHA256
            or receipt.get('reference_sha256') != digest(reference)
            or receipt.get('baseline_sha256') != digest(BASELINE)
            or any(current.get(key) != baseline[key]
                   for key in ('runtime', 'delegate', 'library_sha256', 'models', 'abi'))):
        raise RuntimeError('Invalid same-host official classic text reference')
    return reference


def differences(baseline, current):
    groups = {}
    structural = []

    def visit(old, new, path, group):
        if type(old) is not type(new):
            structural.append(path + ': type differs')
        elif isinstance(old, dict):
            if old.keys() != new.keys():
                structural.append(path + ': keys differ')
            for key in old.keys() & new.keys():
                visit(old[key], new[key], path + '.' + key, old.get('task', group))
        elif isinstance(old, list):
            if len(old) != len(new):
                structural.append(path + ': length differs')
            for i, (left, right) in enumerate(zip(old, new)):
                visit(left, right, f'{path}[{i}]', group)
        elif isinstance(old, (int, float)) and not isinstance(old, bool):
            error = abs(old - new)
            item = groups.setdefault(group, {'maximum_absolute_error': 0.0, 'path': None})
            if error > item['maximum_absolute_error']:
                item.update(maximum_absolute_error=error, path=path,
                            checked_in=old, same_host=new)
        elif old != new:
            structural.append(path + ': value differs')

    for section in ('cases', 'similarities', 'creation_errors', 'lifecycle_sequences'):
        visit(baseline[section], current[section], section, section)
    return {'numeric_groups': groups, 'structural_differences': structural}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--python', type=Path, help='Existing official 1.0.1 environment')
    parser.add_argument('--python-package-root', type=Path, help='Extracted official wheel')
    parser.add_argument('--output-dir', type=Path, default=REPO / 'build/classic-text-reference')
    args = parser.parse_args()
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise SystemExit('Classic text references require macOS arm64.')
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    receipt = output / 'provenance.json'
    receipt.unlink(missing_ok=True)
    python = args.python
    if python is None:
        environment = REPO / 'build/codex-tmp/classic-text-reference-env'
        if not (environment / 'bin/python').exists():
            subprocess.run([sys.executable, '-m', 'venv', str(environment)], check=True)
        python = environment / 'bin/python'
        subprocess.run([str(python), '-m', 'pip', 'install', '--disable-pip-version-check',
                        WHEEL_URL + '#sha256=' + WHEEL_SHA256], check=True)
    reference = output / 'official_reference.json'
    command = [str(python.absolute()), '-B', str(PACKAGE / 'tool/generate_classic_text_reference.py'),
               '--output', str(reference)]
    if args.python_package_root:
        command.extend(['--python-package-root', str(args.python_package_root.resolve())])
    log_file = output / 'official-python.log'
    with log_file.open('w') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    print('\n'.join(log_file.read_text().splitlines()[-15:]), flush=True)
    result.check_returncode()
    summary = differences(json.loads(BASELINE.read_text()), json.loads(reference.read_text()))
    if summary['structural_differences']:
        raise RuntimeError(f'Official reference structure changed: {summary}')
    report = {'source': 'official-python-api', 'runtime': 'mediapipe==1.0.1',
              'delegate': 'CPU', 'library_sha256': LIBRARY_SHA256,
              'wheel_url': WHEEL_URL, 'wheel_sha256': WHEEL_SHA256,
              'os': platform.platform(), 'machine': platform.machine(),
              'reference_sha256': digest(reference), 'baseline_sha256': digest(BASELINE),
              'checked_in_reference_differences': summary}
    receipt.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2), flush=True)


if __name__ == '__main__':
    main()
