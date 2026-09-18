#!/usr/bin/env python3
"""Compare independent candidates against bookending baseline launches."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import statistics


def cases(report):
    result = {}
    for run in report['runs']:
        entry = result.setdefault(run['case'], {'samples': [], 'oracles': []})
        entry['samples'].extend(run['samples_us'])
        entry['oracles'].append(run['landmarks'])
    return result


def summary(entries, stage):
    launch_means = [statistics.mean(s[stage] for s in e['samples']) / 1000 for e in entries]
    samples = sorted(s[stage] / 1000 for e in entries for s in e['samples'])
    return {'mean_ms': statistics.mean(launch_means), 'launch_means_ms': launch_means,
            'p50_ms': samples[math.ceil(len(samples) * .5) - 1],
            'p95_ms': samples[math.ceil(len(samples) * .95) - 1], 'frames': len(samples)}


def compare(reports, schedule):
    if schedule != [0, 0, 0, 1, 1, 0, 0, 2, 2, 0, 0, 3, 3, 0]:
        raise ValueError('Expected two A/A controls followed by three A/B/B/A blocks')
    for key in ('schema', 'frames', 'rounds', 'warmup', 'sdk', 'workload',
                'model_sha256', 'photo_sha256', 'fixtures'):
        if any(r[key] != reports[0][key] for r in reports):
            raise ValueError(f'Incomparable metadata: {key}')
    expected_coverage = sorted((r['case'], r['round']) for r in reports[0]['runs'])
    for report, variant in zip(reports, schedule, strict=True):
        if report['event'] != 'complete' or report['variant'] != variant:
            raise ValueError('Incomplete or incorrect variant')
        if report['device_start']['machine'] != reports[0]['device_start']['machine']:
            raise ValueError('Different devices')
        if report['device_start']['ios'] != reports[0]['device_start']['ios']:
            raise ValueError('Different iOS versions')
        if sorted((r['case'], r['round']) for r in report['runs']) != expected_coverage:
            raise ValueError('Different case/round coverage')
        states = [report['device_start'], report['device_end']]
        states += [r[k] for r in report['runs'] for k in ('device_before', 'device_after') if k in r]
        if any(s['thermal_state'] != 0 or s['low_power_mode'] for s in states):
            raise ValueError('Thermal or Low Power Mode confound')
        expected = report['frames']
        if any(len(run['samples_us']) != expected for run in report['runs']):
            raise ValueError('Incomplete samples')
        if any(not isinstance(v, int) or v < 0 for run in report['runs'] for s in run['samples_us'] for v in s.values()):
            raise ValueError('Invalid sample')
    groups = [cases(r) for r in reports]
    if any(g.keys() != groups[0].keys() for g in groups):
        raise ValueError('Different case coverage')
    rows = []
    maximum_delta = 0
    for case in sorted(groups[0]):
        oracle = groups[0][case]['oracles'][0]
        for group in groups:
            for other in group[case]['oracles']:
                if len(other) != len(oracle) or len(oracle) != 478 * 3:
                    raise ValueError('Incomplete landmark oracle')
                if any(not math.isfinite(v) for v in oracle + other):
                    raise ValueError('Non-finite landmark oracle')
                delta = max(abs(a - b) for a, b in zip(oracle, other, strict=True))
                maximum_delta = max(delta, maximum_delta)
                if delta > 0.0001:
                    raise ValueError(f'Output changed for {case}: {delta}')
        for variant, start in [(1, 2), (2, 6), (3, 10)]:
            before_entries = [groups[start][case], groups[start + 3][case]]
            after_entries = [groups[start + 1][case], groups[start + 2][case]]
            for stage in groups[start][case]['samples'][0]:
                a = summary([groups[0][case]], stage)['mean_ms']
                b = summary([groups[1][case]], stage)['mean_ms']
                noise = 100 * abs(a - b) / statistics.mean([a, b]) if a + b else 0
                floor = max(3.0, noise)
                before, after = summary(before_entries, stage), summary(after_entries, stage)
                reduction = 100 * (1 - after['mean_ms'] / before['mean_ms']) if before['mean_ms'] else 0
                clear = max(after['launch_means_ms']) < min(before['launch_means_ms'])
                verdict = 'improved' if reduction > floor and clear else (
                    'regressed' if reduction < -floor and min(after['launch_means_ms']) > max(before['launch_means_ms']) else 'inconclusive')
                rows.append({'case': case, 'variant': variant, 'stage': stage,
                             'before': before, 'after': after, 'reduction_percent': reduction,
                             'aa_noise_percent': noise, 'acceptance_floor_percent': floor,
                             'verdict': verdict})
    return {'maximum_same_delegate_landmark_delta': maximum_delta, 'comparison': rows}


def load_campaign(directory):
    manifest = json.loads((directory / 'manifest.json').read_text())
    reports = []
    for entry in manifest['runs']:
        raw = (directory / entry['file']).read_bytes()
        if hashlib.sha256(raw).hexdigest() != entry['sha256']:
            raise ValueError('Report hash mismatch')
        reports.append(json.loads(raw))
    if len(reports) != len(manifest['schedule']):
        raise ValueError('Incomplete campaign')
    return reports, manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--staging-repeat', type=Path,
                        help='Unplugged A/B/B/A repeat; uses consecutive unplugged baseline controls from the main campaign')
    args = parser.parse_args()
    reports, manifest = load_campaign(args.directory)
    selected = [str(args.directory / r['file']) for r in manifest['runs']]
    if args.staging_repeat:
        repeat, repeat_manifest = load_campaign(args.staging_repeat)
        if repeat_manifest['schedule'] != [0, 1, 1, 0]:
            raise ValueError('Expected an unplugged staging A/B/B/A repeat')
        # Original staging block predates unplugging. Baselines 9 and 10 are
        # consecutive unchanged launches after unplugging; use those for A/A.
        reports = [reports[9], reports[10], *repeat, *reports[6:]]
        selected = [selected[9], selected[10],
                    *[str(args.staging_repeat / r['file']) for r in repeat_manifest['runs']],
                    *selected[6:]]
    result = compare(reports, manifest['schedule'])
    result['selected_reports'] = selected
    (args.directory / 'comparison.json').write_text(json.dumps(result, indent=2) + '\n')
    lines = ['# iOS face image-storage comparison', '',
             'Positive reduction means faster. Two unchanged A/A launches establish '
             'a per-case noise floor, with a minimum acceptance threshold of 3%. '
             'An improvement also requires both candidate launch means to beat both '
             'bookending baseline means. Launch ranges and pooled percentiles are '
             'descriptive; no frame-level confidence intervals are claimed.', '',
             '| Candidate | Case | Before / after mean ms | Reduction | Verdict |',
             '| --- | --- | ---: | ---: | --- |']
    names = {1: 'FFI reuse', 2: 'Pixel pool', 3: 'Both'}
    for row in result['comparison']:
        if row['stage'] == 'total' and row['case'].endswith('public_api'):
            lines.append(f"| {names[row['variant']]} | {row['case'].removesuffix('/public_api')} "
                         f"| {row['before']['mean_ms']:.3f} / {row['after']['mean_ms']:.3f} "
                         f"| {row['reduction_percent']:.1f}% | {row['verdict']} |")
    text = '\n'.join(lines) + '\n'
    (args.directory / 'comparison.md').write_text(text)
    print(text)


if __name__ == '__main__':
    main()
