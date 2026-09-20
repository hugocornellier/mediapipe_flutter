#!/usr/bin/env python3
"""Compare release launches as experimental units, with repeated bookends."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import statistics
from run_campaign import validate


def load(directory):
    manifest = json.loads((directory / 'manifest.json').read_text())
    reports = []
    if len(manifest['runs']) != len(manifest['config']['schedule']):
        raise ValueError('Incomplete campaign')
    for entry, label in zip(manifest['runs'], manifest['config']['schedule'], strict=True):
        raw = (directory / entry['file']).read_bytes()
        if hashlib.sha256(raw).hexdigest() != entry['sha256']:
            raise ValueError('Report checksum mismatch')
        data = json.loads(raw)
        validate(data, label, data['token'], reports[0] if reports else None)
        reports.append(data)
    return reports, manifest


def summarize(reports, case, stage):
    launches, samples = [], []
    for report in reports:
        frames = [s[stage] / 1000 for r in report['runs'] if r['case'] == case
                  for s in r['samples_us']]
        launches.append(statistics.mean(frames))
        samples.extend(frames)
    samples.sort()
    return {'mean_ms': statistics.mean(launches), 'launch_means_ms': launches,
            'p50_ms': samples[math.ceil(len(samples) * .5) - 1],
            'p95_ms': samples[math.ceil(len(samples) * .95) - 1],
            'launch_sd_ms': statistics.stdev(launches) if len(launches) > 1 else 0,
            'samples': len(samples), 'launches': len(launches)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    reports, manifest = load(args.directory)
    schedule = manifest['config']['schedule']
    if schedule[:2] != ['base', 'base'] or (len(schedule) - 2) % 4:
        raise ValueError('Expected A/A followed by complete A/B/B/A blocks')
    blocks = []
    for index in range(2, len(schedule), 4):
        a, b, c, d = schedule[index:index + 4]
        if a != 'base' or d != 'base' or b != c or b == 'base':
            raise ValueError('Invalid bookended block')
        blocks.append((index, b))
    oracle = {(r['case'], r['round']): r for r in reports[0]['runs']}
    maximum_delta = 0
    for report in reports:
        for run in report['runs']:
            expected = oracle[run['case'], run['round']]
            for key in ('landmarks', 'landmarks_last'):
                values = run[key]
                if len(values) != 1435 or any(not math.isfinite(v) for v in values):
                    raise ValueError('Incomplete or nonfinite oracle')
                delta = max(abs(a - b) for a, b in zip(values, expected[key], strict=True))
                maximum_delta = max(maximum_delta, delta)
                if delta > 0.0001:
                    raise ValueError('Landmark output changed')
            if run['landmarks_sequence_sha256'] != expected['landmarks_sequence_sha256']:
                raise ValueError('Measured frame sequence changed; cannot establish every-frame equivalence')
    cases = sorted({r['case'] for r in reports[0]['runs']})
    rows = []
    for case in cases:
        stages = next(r['samples_us'][0].keys() for r in reports[0]['runs'] if r['case'] == case)
        for stage in stages:
            for report in reports:
                for run in report['runs']:
                    if run['case'] == case and any(set(s) != set(stages) for s in run['samples_us']):
                        raise ValueError('Changed stage coverage')
            # Consecutive unchanged launches include explicit A/A and adjacent
            # bookends. No frames are counted as independent replicates.
            aa_pairs = []
            for i in range(len(schedule) - 1):
                if schedule[i:i + 2] == ['base', 'base']:
                    means = summarize(reports[i:i + 2], case, stage)['launch_means_ms']
                    aa_pairs.append(100 * abs(means[0] - means[1]) / statistics.mean(means)
                                    if sum(means) else 0)
            floor = max(3.0, *aa_pairs)
            for candidate in sorted({b for _, b in blocks}):
                measurements = []
                before_reports, after_reports = [], []
                for start, label in blocks:
                    if label != candidate:
                        continue
                    before_group = [reports[start], reports[start + 3]]
                    after_group = reports[start + 1:start + 3]
                    before_reports.extend(before_group)
                    after_reports.extend(after_group)
                    before = summarize(before_group, case, stage)
                    after = summarize(after_group, case, stage)
                    reduction = 100 * (1 - after['mean_ms'] / before['mean_ms']) if before['mean_ms'] else 0
                    faster = max(after['launch_means_ms']) < min(before['launch_means_ms'])
                    slower = min(after['launch_means_ms']) > max(before['launch_means_ms'])
                    verdict = ('improved' if reduction > floor and faster else
                               'regressed' if reduction < -floor and slower else 'inconclusive')
                    measurements.append({'start_index': start, 'before': before,
                                         'after': after, 'reduction_percent': reduction,
                                         'verdict': verdict})
                before = summarize(before_reports, case, stage)
                after = summarize(after_reports, case, stage)
                verdicts = {m['verdict'] for m in measurements}
                # Both independent blocks must support an improvement/regression.
                verdict = (next(iter(verdicts)) if len(measurements) >= 2 and len(verdicts) == 1
                           else 'inconclusive')
                rows.append({'case': case, 'stage': stage, 'candidate': candidate,
                             'before': before, 'after': after,
                             'reduction_percent': 100 * (1 - after['mean_ms'] / before['mean_ms']) if before['mean_ms'] else 0,
                             'aa_noise_percent': aa_pairs,
                             'acceptance_floor_percent': floor,
                             'blocks': measurements, 'verdict': verdict})
    result = {'maximum_landmark_delta': maximum_delta,
              'every_measured_frame_sequence_matches': True,
              'platform': reports[0]['platform'], 'comparison': rows,
              'selected_reports': [r['file'] for r in manifest['runs']]}
    (args.directory / 'comparison.json').write_text(json.dumps(result, indent=2) + '\n')
    lines = ['# Independent storage audit comparison', '',
             'Launch means are the experimental units. Positive reduction means faster. '
             'Acceptance requires both repeated blocks to beat the larger of 3% and '
             'all observed consecutive baseline A/A differences, with each candidate '
             'launch beating both bookends. Percentiles describe correlated frames.', '',
             '| Candidate | Case | Before / after ms | Reduction | Floor | Verdict |',
             '| --- | --- | ---: | ---: | ---: | --- |']
    for row in rows:
        if row['stage'] == 'total' and row['case'].endswith('public_api'):
            lines.append(f"| {row['candidate']} | {row['case']} | "
                         f"{row['before']['mean_ms']:.3f} / {row['after']['mean_ms']:.3f} | "
                         f"{row['reduction_percent']:.2f}% | {row['acceptance_floor_percent']:.2f}% | {row['verdict']} |")
    output = '\n'.join(lines) + '\n'
    (args.directory / 'comparison.md').write_text(output)
    print(output)


if __name__ == '__main__':
    main()
