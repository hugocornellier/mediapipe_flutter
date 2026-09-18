#!/usr/bin/env python3
"""Run retained release apps without rebuilding during timed measurements."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time


def run(args, log):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    log.write_text(result.stdout)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed; see {log}\n{result.stdout[-2000:]}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--apps', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--schedule', default='0,0,0,1,1,0,0,2,2,0,0,3,3,0')
    parser.add_argument('--resume', action='store_true')
    parser.add_argument('--cooldown', type=int, default=45)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    schedule = [int(v) for v in args.schedule.split(',')]
    receipts = {}
    for variant in sorted(set(schedule)):
        app = args.apps / str(variant) / 'Runner.app'
        if not app.is_dir():
            raise ValueError(f'Missing retained app: {app}')
        receipt = json.loads((app.parent / 'receipt.json').read_text())
        for path in app.rglob('*'):
            if path.is_file() and path.name in ('App', 'mediapipe_ios'):
                expected = receipt[str(path)]
                if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                    raise ValueError(f'Retained artifact changed: {path}')
        receipts[str(variant)] = receipt
    manifest = {'schedule': schedule, 'receipts': receipts, 'runs': []}
    manifest_file = args.output / 'manifest.json'
    if args.resume:
        manifest = json.loads(manifest_file.read_text())
        if manifest['schedule'] != schedule or manifest['receipts'] != receipts:
            raise ValueError('Resume artifacts or schedule changed')
        for entry in manifest['runs']:
            if hashlib.sha256((args.output / entry['file']).read_bytes()).hexdigest() != entry['sha256']:
                raise ValueError('Resume report hash mismatch')
    elif manifest_file.exists():
        raise ValueError('Campaign already exists; use --resume')
    manifest_file.write_text(json.dumps(manifest, indent=2) + '\n')
    for index, variant in enumerate(schedule):
        if index < len(manifest['runs']):
            continue
        print(f'COOLING {args.cooldown}s before benchmark {index + 1}', flush=True)
        # Short waits keep progress observable while the physical device cools.
        remaining = args.cooldown
        while remaining > 0:
            interval = min(remaining, 30)
            time.sleep(interval)
            remaining -= interval
        name = f'{index:02d}-v{variant}'
        report = args.output / f'{name}.json'
        if report.exists():
            raise ValueError(f'Refusing to overwrite {report}')
        print(f'BENCHMARK {index + 1}/{len(schedule)}: variant {variant}', flush=True)
        app = (args.apps / str(variant) / 'Runner.app').resolve()
        run(['xcrun', 'devicectl', 'device', 'install', 'app', '--device', args.device,
             str(app)], args.output / f'{name}-install.log')
        run(['xcrun', 'devicectl', 'device', 'process', 'launch', '--device', args.device,
             '--console', 'com.example.mediapipeGallery', '--', '--mediapipe-benchmark'],
            args.output / f'{name}-console.log')
        run(['xcrun', 'devicectl', 'device', 'copy', 'from', '--device', args.device,
             '--domain-type', 'appDataContainer', '--domain-identifier', 'com.example.mediapipeGallery',
             '--source', 'tmp/gallery-ios-face-benchmark.json', '--destination', str(report.resolve())],
            args.output / f'{name}-copy.log')
        data = json.loads(report.read_text())
        if data.get('event') != 'complete' or data['variant'] != variant:
            raise ValueError(f'Incomplete or wrong variant: {report}')
        states = [data['device_start'], data['device_end']]
        states += [r[key] for r in data['runs'] for key in ('device_before', 'device_after') if key in r]
        if any(s['thermal_state'] != 0 or s['low_power_mode'] for s in states):
            raise ValueError(f'Thermal or Low Power Mode confound: {report}; raw data retained')
        if manifest['runs']:
            first = json.loads((args.output / manifest['runs'][0]['file']).read_text())
            for key in ('schema', 'frames', 'rounds', 'warmup', 'sdk', 'workload',
                        'model_sha256', 'photo_sha256', 'fixtures'):
                if data[key] != first[key]:
                    raise ValueError(f'Changed {key}: {report}; raw data retained')
            for key in ('machine', 'ios'):
                if data['device_start'][key] != first['device_start'][key]:
                    raise ValueError(f'Changed device {key}: {report}; raw data retained')
        manifest['runs'].append({'file': report.name, 'sha256': hashlib.sha256(report.read_bytes()).hexdigest()})
        manifest_file.write_text(json.dumps(manifest, indent=2) + '\n')
        print(f'SAVED {report.name}: all correctness checks passed, nominal thermal state', flush=True)


if __name__ == '__main__':
    main()
