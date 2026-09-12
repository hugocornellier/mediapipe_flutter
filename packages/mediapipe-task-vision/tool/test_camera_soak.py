"""Run a release camera soak and save timing/memory metrics, never camera images.

Requires macOS arm64, Xcode, Flutter and a camera. Defaults to 15 active minutes
and five start/stop cycles. Leaves the built app as the diagnostic target;
rebuild with `flutter build macos --release -t lib/main.dart` for normal use.
"""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
from threading import Timer

from prepare_face_example import prepare

PACKAGE = Path(__file__).resolve().parents[1]
EXAMPLE = PACKAGE / 'example'


def summarize(events):
    samples = [event for event in events if event['event'] == 'sample']
    # Exclude the first 30 active seconds of each new camera/task instance.
    warmed = [sample for sample in samples
              if sample['active_seconds'] - sample['window_seconds'] >= 30]
    memory_samples = warmed or samples
    first = memory_samples[:4]
    last = memory_samples[-4:]
    mib = 1024 * 1024
    median_rss = lambda values: statistics.median(s['rss_bytes'] for s in values) / mib
    elapsed = [sample['elapsed_seconds'] / 60 for sample in memory_samples]
    memory = [sample['rss_bytes'] / mib for sample in memory_samples]
    slope = None
    if len(elapsed) > 1:
        slope = statistics.linear_regression(elapsed, memory).slope
    final = next((event for event in reversed(events) if event['event'] == 'complete'), None)
    return {
        'completed': final is not None,
        'total_frames': final['total_frames'] if final else None,
        'fixture_frames': final['fixture_frames'] if final else None,
        'frames_with_faces': final['frames_with_faces'] if final else None,
        'maximum_landmarks': final['maximum_landmarks'] if final else None,
        'completed_cycles': final['completed_cycles'] if final else None,
        'measured_seconds': sum(s['window_seconds'] for s in samples),
        'active_fps': sum(s['window_frames'] for s in samples) /
                      sum(s['window_seconds'] for s in samples),
        'skipped_frames': sum(s['window_skipped'] for s in samples),
        'median_window_p50_ms': statistics.median(s['latency_p50_ms'] for s in samples
                                                if s['latency_p50_ms'] is not None),
        'maximum_window_p95_ms': max(s['latency_p95_ms'] for s in samples
                                    if s['latency_p95_ms'] is not None),
        'fixture_maximum_window_p95_ms': max(s['fixture_latency_p95_ms'] for s in samples),
        'early_rss_mib': median_rss(first),
        'late_rss_mib': median_rss(last),
        'rss_growth_mib': median_rss(last) - median_rss(first),
        'rss_slope_mib_per_minute': slope,
        'peak_rss_mib': max(s['peak_rss_bytes'] for s in events) / mib,
        'memory_note': 'RSS is observational; allocator/cache growth is not by itself proof of a leak.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=int, default=900)
    parser.add_argument('--cycles', type=int, default=5)
    args = parser.parse_args()
    if not (1 <= args.cycles <= 100 and args.cycles * 10 <= args.seconds <= 7200):
        parser.error('Use 1–100 cycles, at least 10 seconds per cycle, and at most 7200 seconds')
    output = PACKAGE.parents[1] / 'build' / ('camera-soak-' +
             datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    output.mkdir(parents=True)
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=PACKAGE, text=True).strip()
    portrait = (PACKAGE / 'test/fixtures/face_detection/portrait-301x209.rgb').read_bytes()
    definitions = output / 'dart_defines.json'
    definitions.write_text(json.dumps({
        'CAMERA_SOAK_SECONDS': args.seconds, 'CAMERA_SOAK_CYCLES': args.cycles,
        'CAMERA_SOAK_PORTRAIT': base64.b64encode(portrait).decode(),
    }))
    (output / 'configuration.json').write_text(json.dumps({
        'revision': revision, 'active_seconds': args.seconds, 'cycles': args.cycles,
        'portrait_sha256': hashlib.sha256(portrait).hexdigest(),
        'flutter': subprocess.check_output(['flutter', '--version'], text=True),
    }, indent=2) + '\n')
    print(f'Soak artifacts: {output}', flush=True)
    for downloader in ('download_model.dart', 'download_face_landmarker.dart'):
        subprocess.run(['dart', f'tool/{downloader}'], cwd=PACKAGE, check=True)
    prepare()
    subprocess.run(['flutter', 'build', 'macos', '--release', '-t', 'tool/release_camera_soak.dart',
                    f'--dart-define-from-file={definitions}'], cwd=EXAMPLE, check=True)
    executable = EXAMPLE / ('build/macos/Build/Products/Release/'
                 'mediapipe_face_camera.app/Contents/MacOS/mediapipe_face_camera')
    events = []
    timed_out = []
    with (output / 'process.log').open('w') as log, (output / 'metrics.jsonl').open('w') as metrics:
        process = subprocess.Popen([str(executable)], cwd=EXAMPLE, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, bufsize=1)
        def timeout():
            timed_out.append(True)
            process.terminate()
        watchdog = Timer(args.seconds + args.cycles * 45 + 150, timeout)
        watchdog.start()
        try:
            for line in process.stdout:
                log.write(line)
                log.flush()
                print(line, end='', flush=True)
                if line.startswith('CAMERA_SOAK '):
                    event = json.loads(line.removeprefix('CAMERA_SOAK '))
                    events.append(event)
                    metrics.write(json.dumps(event) + '\n')
                    metrics.flush()
            result = process.wait()
        finally:
            watchdog.cancel()
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=15)
    if any(event['event'] == 'sample' for event in events):
        summary = summarize(events)
        (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(json.dumps(summary, indent=2), flush=True)
    if timed_out or result != 0 or not events or events[-1]['event'] != 'complete':
        raise SystemExit(f'Soak failed; inspect {output}')
    print(f'Camera soak completed. Metrics: {output / "summary.json"}', flush=True)


if __name__ == '__main__':
    main()
