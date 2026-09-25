"""Generate an independent Audio Classifier reference on the host running the tests.

Uses Google's checksum-pinned wheel for this host and never rewrites the
checked-in reference or changes test tolerances. Set
MEDIAPIPE_AUDIO_REFERENCE_DIR to the output directory to test against it.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys

from generate_audio_reference import FIXTURES, PACKAGE, host_runtime
from official_wheels import venv_python

REPO = PACKAGE.parents[1]
BASELINE = FIXTURES / 'official_reference.json'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def differences(baseline, current):
    """The largest score difference per clip, and any change in shape."""
    structural = []
    scores = {}
    if baseline['clips'].keys() != current['clips'].keys():
        structural.append('clips differ')
    for clip in baseline['clips'].keys() & current['clips'].keys():
        old, new = baseline['clips'][clip], current['clips'][clip]
        if [c['timestamp_ms'] for c in old] != [c['timestamp_ms'] for c in new]:
            structural.append(f'{clip}: chunk timestamps differ')
            continue
        error = 0.0
        for i, (left, right) in enumerate(zip(old, new)):
            names = {name for name, _ in left['top']}
            if names != {name for name, _ in right['top']}:
                structural.append(f'{clip}[{i}]: top categories differ')
                continue
            expected = dict(left['top'])
            error = max([error, *(abs(expected[name] - score) for name, score in right['top'])])
        scores[clip] = error
    return {'maximum_score_error': scores, 'structural_differences': structural}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--python', type=Path, help='Existing environment with the pinned wheel')
    parser.add_argument('--output-dir', type=Path, default=REPO / 'build/audio-reference')
    args = parser.parse_args()
    runtime = host_runtime()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    receipt = output / 'provenance.json'
    receipt.unlink(missing_ok=True)
    python = args.python
    if python is None:
        environment = REPO / f'build/codex-tmp/official-python-{runtime["version"]}'
        python = venv_python(environment)
        if not python.exists():
            subprocess.run([sys.executable, '-m', 'venv', str(environment)], check=True)
        subprocess.run([str(python), '-m', 'pip', 'install', '--disable-pip-version-check',
                        runtime['wheel_url'] + '#sha256=' + runtime['wheel_sha256']], check=True)
    reference = output / 'official_reference.json'
    log_file = output / 'official-python.log'
    with log_file.open('w', encoding='utf-8') as log:
        result = subprocess.run([str(python.absolute()), '-B',
                                 str(PACKAGE / 'tool/generate_audio_reference.py'),
                                 '--output', str(reference)],
                                stdout=log, stderr=subprocess.STDOUT)
    print('\n'.join(log_file.read_text(encoding='utf-8', errors='replace').splitlines()[-10:]),
          flush=True)
    result.check_returncode()
    summary = differences(json.loads(BASELINE.read_text(encoding='utf-8')),
                          json.loads(reference.read_text(encoding='utf-8')))
    report = {'source': 'official-python-api', 'runtime': 'mediapipe==' + runtime['version'],
              'delegate': 'CPU', 'library_sha256': runtime['library_sha256'],
              'wheel_url': runtime['wheel_url'], 'wheel_sha256': runtime['wheel_sha256'],
              'os': platform.platform(), 'machine': platform.machine(),
              'reference_sha256': digest(reference), 'baseline_sha256': digest(BASELINE),
              'checked_in_reference_differences': summary}
    receipt.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2), flush=True)


if __name__ == '__main__':
    main()
