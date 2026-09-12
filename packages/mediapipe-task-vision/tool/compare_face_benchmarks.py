#!/usr/bin/env python3
"""Compare repeated pipeline runs, checking provenance and retaining variability."""

import argparse
import gzip
import hashlib
import json
import math
from pathlib import Path
import statistics


def load(prefix):
    raw = Path(str(prefix) + '.json.gz').read_bytes()
    summary = json.loads(Path(str(prefix) + '.summary.json').read_text())
    if hashlib.sha256(raw).hexdigest() != summary['raw_sha256']:
        raise ValueError(f'Raw log hash mismatch: {prefix}')
    report = json.loads(gzip.decompress(raw))
    if report['metadata'] != summary['metadata']:
        raise ValueError(f'Metadata mismatch: {prefix}')
    expected = report['metadata']['frames']
    for run in report['runs']:
        if len(run['samples_us']) != expected:
            raise ValueError(f'Incomplete samples: {prefix}')
        for sample in run['samples_us']:
            if any(not isinstance(v, int) or v < 0 for v in sample.values()):
                raise ValueError(f'Invalid timing: {prefix}')
    return report


def aggregate(reports):
    groups = {}
    for report in reports:
        for run in report['runs']:
            for stage in run['samples_us'][0]:
                entry = groups.setdefault((run['case'], stage), ([], []))
                values = [sample[stage] / 1000 for sample in run['samples_us']]
                entry[0].append(statistics.mean(values))
                entry[1].extend(values)
    result = {}
    for key, (means, samples) in groups.items():
        samples.sort()
        result[key] = {
            'mean_ms': statistics.mean(means),
            'round_mean_min_ms': min(means),
            'round_mean_max_ms': max(means),
            'round_means_ms': means,
            'pooled_p50_ms': samples[math.ceil(.5 * len(samples)) - 1],
            'pooled_p95_ms': samples[math.ceil(.95 * len(samples)) - 1],
            'pooled_p99_ms': samples[math.ceil(.99 * len(samples)) - 1],
            'samples': len(samples),
        }
    return result


def compare(baseline, candidate):
    reports = baseline + candidate
    # Exact equality is intentional: this comparison changes only Dart code.
    for key in ['schema', 'dart', 'os', 'hardware', 'model_sha256',
                'fixture_sha256', 'libraries_sha256', 'frames', 'rounds',
                'warmup_frames', 'order_seed', 'workload']:
        if any(r['metadata'][key] != reports[0]['metadata'][key] for r in reports):
            raise ValueError(f'Incomparable run metadata: {key}')
    for group in (baseline, candidate):
        if len({r['metadata']['executable_sha256'] for r in group}) != 1:
            raise ValueError('Each variant must use one retained executable')
    expected = sorted((r['case'], r['round']) for r in reports[0]['runs'])
    if any(sorted((r['case'], r['round']) for r in report['runs']) != expected
           for report in reports):
        raise ValueError('Case/round coverage differs')
    before, after = aggregate(baseline), aggregate(candidate)
    if before.keys() != after.keys():
        raise ValueError('Timing stages differ')
    return [
        {
            'case': case, 'stage': stage, 'baseline': before[case, stage],
            'candidate': after[case, stage],
            'mean_reduction_percent': 100 * (
                1 - after[case, stage]['mean_ms'] / before[case, stage]['mean_ms']
            ) if before[case, stage]['mean_ms'] else None,
        }
        for case, stage in sorted(before)
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', nargs='+', type=Path, required=True)
    parser.add_argument('--candidate', nargs='+', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    rows = compare([load(p) for p in args.baseline],
                   [load(p) for p in args.candidate])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.with_suffix('.json').write_text(json.dumps({
        'baseline_runs': [str(p) for p in args.baseline],
        'candidate_runs': [str(p) for p in args.candidate],
        'comparison': rows,
    }, indent=2) + '\n')
    lines = [
        '# Face pipeline comparison', '',
        'Positive reduction means faster. Means weight each round equally; '
        'percentiles pool frames and are descriptive, not confidence intervals. '
        'See JSON for individual round means and their ranges.', '',
        '| Input / delegate | Before mean / p95 ms | After mean / p95 ms | Mean reduction |',
        '| --- | ---: | ---: | ---: |',
    ]
    for row in rows:
        if not row['case'].endswith('/public_api') or row['stage'] != 'total':
            continue
        a, b = row['baseline'], row['candidate']
        lines.append(
            f"| {row['case'].removesuffix('/public_api')} "
            f"| {a['mean_ms']:.3f} / {a['pooled_p95_ms']:.3f} "
            f"| {b['mean_ms']:.3f} / {b['pooled_p95_ms']:.3f} "
            f"| {row['mean_reduction_percent']:.1f}% |"
        )
    text = '\n'.join(lines) + '\n'
    args.output.with_suffix('.md').write_text(text)
    print(text)


if __name__ == '__main__':
    main()
