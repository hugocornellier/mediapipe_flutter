"""Run CPU face-task integration tests in an installed arm64 iOS simulator."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess

from prepare_face_example import PACKAGE, prepare


def capture(args):
    return subprocess.check_output(args, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', help='Simulator UUID; defaults to a booted iOS simulator')
    args = parser.parse_args()
    devices = json.loads(capture(['xcrun', 'simctl', 'list', 'devices', 'available', '--json']))['devices']
    available = [(runtime, device) for runtime, entries in devices.items()
                 if '.iOS-' in runtime for device in entries]
    candidates = [(runtime, device) for runtime, device in available
                  if device['udid'] == args.device] if args.device else [
                      (runtime, device) for runtime, device in available if device['state'] == 'Booted']
    if not candidates:
        raise SystemExit('Specify an installed iOS simulator with --device UUID, or boot one first.')
    runtime, device = candidates[0]
    directory = PACKAGE / 'build/native/ios-simulator/arm64'
    library = directory / 'libmediapipe.dylib'
    if not library.exists():
        raise SystemExit('Run python3 -B tool/build_ios_simulator.py first.')
    libraries = {'combined': {
        'sha256': hashlib.sha256(library.read_bytes()).hexdigest(),
        'manifest': json.loads((directory / 'manifest.json').read_text()),
    }}
    prepare()
    if device['state'] != 'Booted':
        subprocess.run(['xcrun', 'simctl', 'boot', device['udid']], check=True)
    subprocess.run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b'], check=True, timeout=180)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    output = PACKAGE.parents[1] / f'build/ios-simulator-test-{stamp}'
    output.mkdir(parents=True)
    command = ['flutter', 'test', '-d', device['udid'],
               'integration_test/ios_cpu_test.dart', '--reporter', 'expanded']
    git_head = capture(['git', '-C', str(PACKAGE), 'rev-parse', 'HEAD'])
    git_status = capture(['git', '-C', str(PACKAGE), 'status', '--porcelain'])
    print(f'Running CPU integration tests; log: {output / "flutter-test.log"}', flush=True)
    with (output / 'flutter-test.log').open('w') as log:
        result = subprocess.run(command, cwd=PACKAGE / 'example', stdout=log,
                                stderr=subprocess.STDOUT, timeout=1200)
    report = {
        'started_utc': stamp, 'device': device['udid'], 'device_name': device['name'],
        'runtime': runtime, 'command': command, 'exit_code': result.returncode,
        'git_head': git_head, 'git_status': git_status,
        'libraries': libraries,
        'scope': 'Flutter debug simulator integration; not physical-device or camera performance.',
    }
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('\n'.join((output / 'flutter-test.log').read_text().splitlines()[-35:]))
    print(f'Report: {output / "report.json"}')
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
