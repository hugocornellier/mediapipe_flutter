#!/usr/bin/env python3
"""Run retained storage-audit release artifacts; never build during a campaign."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time

BUNDLE = 'com.example.mediapipeGallery'
DEFAULT = ['base', 'base', 'base', 'm0', 'm0', 'base'] + [
    label for _ in range(2) for candidate in ('m1', 'm2', 'm3')
    for label in ('base', candidate, candidate, 'base')
]


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def command(args, log, timeout=300):
    with log.open('x') as stream:
        result = subprocess.run(args, stdout=stream, stderr=subprocess.STDOUT,
                                timeout=timeout)
    if result.returncode:
        raise RuntimeError(f'Command failed ({result.returncode}): {log}')


def device_states(data):
    return [data[key] for key in ('device_start', 'device_after_settle', 'device_end')
            if key in data] + [run[key] for run in data.get('runs', [])
                              for key in ('device_before', 'device_after')]


def validate(data, label, token, first=None):
    if data.get('event') != 'complete' or data.get('artifact') != label:
        raise ValueError('Incomplete or wrong artifact report')
    if data.get('token') != token:
        raise ValueError('Stale report token')
    states = device_states(data)
    if any(s['thermal_state'] != 0 or s['low_power_mode'] for s in states):
        raise ValueError('Thermal or Low Power Mode confound')
    power_key = 'battery_state' if data['platform'] == 'ios' else 'power_source'
    if len({s[power_key] for s in states}) != 1:
        raise ValueError('Charging condition changed within launch')
    if data['mode'] == 'timed':
        expected = {(f"{f['width']}x{f['height']}/{delegate}/{kind}", round_)
                    for f in data['fixtures'] for delegate in ('cpu', 'gpu')
                    for kind in ('tight/public_api', '33ms/public_api',
                                 'tight/native_profile')
                    for round_ in range(data['rounds'])}
        actual = [(r['case'], r['round']) for r in data['runs']]
        if len(actual) != len(expected) or set(actual) != expected:
            raise ValueError('Incomplete or duplicate case coverage')
        for run in data['runs']:
            if len(run['samples_us']) != data['frames']:
                raise ValueError('Incomplete frame samples')
            if any(type(v) is not int or v < 0 for s in run['samples_us']
                   for v in s.values()):
                raise ValueError('Invalid frame sample')
    else:
        checks = data['validation']
        if any(not all(v.values()) for k, v in checks.items() if 'strides' in k):
            raise ValueError('Stride validation failed')
        if any(not all(v) for k, v in checks.items() if 'alternation' in k):
            raise ValueError('Face/blank or dimension-change validation failed')
    if first is not None:
        for key in ('schema', 'harness', 'platform', 'mode', 'frames', 'rounds',
                    'warmup', 'period_us', 'sdk', 'model_sha256', 'fixtures',
                    'official_ios_runtime'):
            if data[key] != first[key]:
                raise ValueError(f'Changed {key}')
        for key in ('machine', power_key):
            if data['device_after_settle'][key] != first['device_after_settle'][key]:
                raise ValueError(f'Changed device condition: {key}')
        if data['mode'] == 'timed':
            reference = {(r['case'], r['round']): r for r in first['runs']}
            for run in data['runs']:
                expected = reference[run['case'], run['round']]
                if run['landmarks_sequence_sha256'] != expected['landmarks_sequence_sha256']:
                    raise ValueError('Measured landmark sequence changed')
        else:
            for key, value in data['validation'].items():
                if ('reference' in key or 'video_sequence' in key) and 'strides' not in key:
                    if value != first['validation'][key]:
                        raise ValueError(f'Validation output changed: {key}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=('ios', 'macos'), required=True)
    parser.add_argument('--device')
    parser.add_argument('--apps', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--schedule', default=','.join(DEFAULT))
    parser.add_argument('--cooldown', type=int, default=60)
    parser.add_argument('--settle', type=int, default=10)
    parser.add_argument('--validate', action='store_true')
    parser.add_argument('--resume', action='store_true')
    args = parser.parse_args()
    if args.platform == 'ios' and not args.device:
        parser.error('--device required for iOS')
    schedule = args.schedule.split(',')
    artifacts = {}
    apps = {}
    for label in sorted(set(schedule)):
        folder = args.apps / label
        receipt = json.loads((folder / 'receipt.json').read_text())
        app, = folder.glob('*.app')
        files = {str(p.relative_to(app)): sha(p) for p in sorted(app.rglob('*'))
                 if p.is_file()}
        for name, expected in receipt['binaries'].items():
            binary_name = 'mediapipe_gallery' if name == 'Runner' and args.platform == 'macos' else name
            found = {digest for path, digest in files.items()
                     if Path(path).name == binary_name}
            if found != {expected}:
                raise ValueError(f'Receipt mismatch: {label}/{name}')
        artifacts[label] = {'receipt': receipt, 'files': files}
        apps[label] = app.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    manifest_path = args.output / 'manifest.json'
    config = {'platform': args.platform, 'device': args.device,
              'schedule': schedule, 'cooldown_s': args.cooldown,
              'settle_s': args.settle, 'validation': args.validate,
              'artifacts': artifacts}
    if args.resume:
        manifest = json.loads(manifest_path.read_text())
        if manifest['config'] != config:
            raise ValueError('Resume configuration or artifacts changed')
        for entry in manifest['runs']:
            if sha(args.output / entry['file']) != entry['sha256']:
                raise ValueError('Resume report changed')
    else:
        if manifest_path.exists():
            raise ValueError('Existing campaign; use --resume')
        manifest = {'config': config, 'runs': [], 'rejected': []}
    def save():
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    save()
    first = (json.loads((args.output / manifest['runs'][0]['file']).read_text())
             if manifest['runs'] else None)
    for index, label in enumerate(schedule):
        if index < len(manifest['runs']):
            continue
        attempt = len([r for r in manifest['rejected'] if r['index'] == index])
        token = f'{args.platform}-{index:02d}-{label}-a{attempt}'
        name = f'{index:02d}-{label}-a{attempt}'
        report = args.output / f'{name}.json'
        if report.exists():
            raise ValueError(f'Refusing to overwrite {report}')
        print(f'COOLING {args.cooldown}s; launch {index + 1}/{len(schedule)} {label}', flush=True)
        for remaining in range(args.cooldown, 0, -10):
            time.sleep(min(10, remaining))
        launch_args = ['--mediapipe-benchmark', f'--bench-token={token}',
                       f'--bench-settle={args.settle}']
        if args.validate:
            launch_args.append('--bench-validate')
        console = args.output / f'{name}-console.log'
        try:
            if args.platform == 'ios':
                command(['xcrun', 'devicectl', 'device', 'install', 'app',
                         '--device', args.device, str(apps[label])],
                        args.output / f'{name}-install.log')
                command(['xcrun', 'devicectl', 'device', 'process', 'launch',
                         '--device', args.device, '--console', BUNDLE, '--',
                         *launch_args], console, timeout=600)
                command(['xcrun', 'devicectl', 'device', 'copy', 'from',
                         '--device', args.device, '--domain-type', 'appDataContainer',
                         '--domain-identifier', BUNDLE, '--source',
                         f'tmp/storage-audit-{token}.json', '--destination',
                         str(report.resolve())], args.output / f'{name}-copy.log')
            else:
                executable = apps[label] / 'Contents/MacOS/mediapipe_gallery'
                command([str(executable), *launch_args], console, timeout=600)
                match = re.search(r'STORAGE_AUDIT_REPORT (.+)', console.read_text())
                if not match:
                    raise ValueError('No report path in console')
                shutil.copyfile(match[1].strip(), report)
            data = json.loads(report.read_text())
            validate(data, label, token, first)
        except Exception as error:
            manifest['rejected'].append({'index': index, 'label': label,
                                         'file': report.name, 'reason': str(error),
                                         'at': datetime.datetime.now(datetime.timezone.utc).isoformat()})
            save()
            raise
        manifest['runs'].append({'file': report.name, 'sha256': sha(report)})
        save()
        if first is None:
            first = data
        print(f'SAVED {report.name}: complete, fixed pixels, nominal thermal state', flush=True)


if __name__ == '__main__':
    main()
