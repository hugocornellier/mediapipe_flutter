"""Capture what a Windows vision worker is doing when one of its phases stalls.

Run after tool/test_desktop.py has prepared its Windows consumer. It reruns the
landmark and segmenter test files (one file at a time, both at once, or the
whole suite) with MEDIAPIPE_VISION_TRACE=1. A watchdog pairs every worker's
trace phases: spawn, native creation, each native call, delivery of its result
to the test isolate, and isolate exit. When a phase stays open for
STALL_SECONDS, Windows' cdb records each thread's CPU time, the process's held
critical sections, its modules and every thread's stack, and again at
SECOND_DUMP_SECONDS, so a blocked thread can be told from a busy one. Writes
build/windows-stall-probe/.
"""
import collections
import json
import os
from pathlib import Path
import re
import subprocess
import threading
import time

PACKAGE = Path(__file__).resolve().parents[1]
REPO = PACKAGE.parents[1]
OUT = REPO / os.environ.get('PROBE_OUT', 'build/windows-stall-probe')
STALL_SECONDS = float(os.environ.get('PROBE_STALL_SECONDS', '5'))
SECOND_DUMP_SECONDS = 15
MAX_STALLS_DUMPED = 4  # per run
RUNS = int(os.environ.get('PROBE_RUNS', '4'))
MODES = os.environ.get('PROBE_MODES', 'serial,concurrent').split(',')
FILES = ['test/landmark_tasks_test.dart', 'test/segmenter_tasks_test.dart']
MODE_ARGS = {'full': ([], []), 'concurrent': ([], FILES),
             'serial': (['--concurrency=1'], FILES)}
TRACE = re.compile(r'MPTRACE (\d+) pid=(\d+) tag=(\d+) (.+?) #(\S+) '
                   r'(start|end|error|received|return|exited)')
SYMBOLS = r'srv*C:\symbols*https://msdl.microsoft.com/download/symbols'
DEBUGGERS = [Path(r'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64'),
             Path(r'C:\Program Files\Windows Kits\10\Debuggers\x64')]
PREWARM = ['ntdll.dll', 'kernel32.dll', 'KernelBase.dll', 'ucrtbase.dll',
           'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll',
           'ws2_32.dll', 'combase.dll', 'rpcrt4.dll', 'advapi32.dll',
           'bcryptprimitives.dll', 'dbghelp.dll']
SNAPSHOT = r'''
$p = Get-Process -Id {pid} -ErrorAction SilentlyContinue
if ($p) {{ "test process: cpu_s=$([math]::Round($p.CPU,1)) threads=$($p.Threads.Count) handles=$($p.HandleCount) private_mb=$([int]($p.PrivateMemorySize64/1MB))" }}
$os = Get-CimInstance Win32_OperatingSystem
"free_mb=$([int]($os.FreePhysicalMemory/1KB)) of $([int]($os.TotalVisibleMemorySize/1KB))"
Get-Process | Sort-Object CPU -Descending | Select-Object -First 12 Name,Id,
  @{{n='CPU_s';e={{[math]::Round($_.CPU,1)}}}},
  @{{n='WS_MB';e={{[int]($_.WS/1MB)}}}},
  @{{n='Threads';e={{$_.Threads.Count}}}} | Format-Table -AutoSize | Out-String -Width 200
'''


def debugger(name):
    return next((d / name for d in DEBUGGERS if (d / name).exists()), None)


def consumer():
    roots = sorted((REPO / 'build/codex-tmp').glob('desktop-windows-*'),
                   key=lambda p: p.stat().st_mtime)
    if not roots:
        raise SystemExit('Run tool/test_desktop.py first.')
    return roots[-1]


def prewarm():
    """Fetch system symbols up front so a stall's first dump is quick."""
    symchk = debugger('symchk.exe')
    if symchk is None:
        return 'symchk.exe not found; symbols load during the first dump'
    started = time.time()
    system = Path(os.environ.get('SystemRoot', r'C:\Windows')) / 'System32'
    for dll in PREWARM:
        if (system / dll).exists():
            subprocess.run([str(symchk), str(system / dll), '/s', SYMBOLS],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           timeout=300)
    return f'symbols prewarmed in {time.time() - started:.0f} s'


def dump(pid, target, header, level):
    """Thread CPU times, held critical sections, modules and all stacks.

    Noninvasive attach: the process is suspended only while cdb reads it, then
    cdb detaches. cdb logs to a file so a full pipe can never block it.
    """
    commands = ('.reload; !runaway 7; ~*k 80; qd' if level > 1 else
                '.reload; !runaway 7; !locks; ~*k 80; lm; qd')
    log = target.with_name(target.stem + '.cdb.txt')
    started = time.time()
    try:
        subprocess.run([str(debugger('cdb.exe')), '-pv', '-p', str(pid),
                        '-y', SYMBOLS, '-logo', str(log), '-c', commands],
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=300)
        note = f'cdb finished in {time.time() - started:.1f} s'
    except subprocess.TimeoutExpired:
        note = 'cdb timed out'
    snapshot = subprocess.run(
        ['powershell', '-NoProfile', '-Command', SNAPSHOT.format(pid=pid)],
        capture_output=True, text=True, timeout=120)
    target.write_text(f'{header}\n{note}\n\n{snapshot.stdout}{snapshot.stderr}\n',
                      encoding='utf-8')


def run(label, extra, files):
    root = consumer()
    env = {**os.environ, 'MEDIAPIPE_VISION_TRACE': '1',
           'MEDIAPIPE_CPU_REFERENCE_DIR': str(root / 'reference')}
    log = (OUT / f'{label}.log').open('w', encoding='utf-8')
    started = time.time()
    process = subprocess.Popen(
        ['dart.bat' if os.name == 'nt' else 'dart', 'test', *extra, *files,
         '--reporter', 'expanded'],
        cwd=root / 'app', env=env, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace')
    phases = {}  # (pid, tag, kind, request) -> open phase
    stalls = []
    dumps = []
    lock = threading.Lock()

    def start_dump(key, phase, level):
        stall = phase['stall']
        target = OUT / f'stacks-{label}-{stall["number"]}-{level}.txt'
        header = json.dumps({**stall, 'level': level, 'seconds_open':
                             round(time.time() - phase['opened'], 1)})
        thread = threading.Thread(target=dump, args=(key[0], target, header, level))
        thread.start()
        dumps.append(thread)

    def watchdog():
        while process.poll() is None:
            now = time.time()
            with lock:
                for key, phase in phases.items():
                    if key[2] == 'spawn':
                        continue  # failed creations never end this phase
                    age = now - phase['opened']
                    if (phase['level'] == 0 and age > STALL_SECONDS
                            and len(stalls) < MAX_STALLS_DUMPED):
                        phase['level'] = 1
                        phase['stall'] = {'number': len(stalls) + 1,
                                          'pid': key[0], 'tag': key[1],
                                          'task': phase['task'],
                                          'phase': key[2], 'request': key[3]}
                        stalls.append(phase['stall'])
                        start_dump(key, phase, 1)
                    elif phase['level'] == 1 and age > SECOND_DUMP_SECONDS:
                        phase['level'] = 2
                        start_dump(key, phase, 2)
            time.sleep(0.5)

    def open_phase(key, task):
        phases[key] = {'opened': time.time(), 'level': 0, 'task': task}

    def close_phase(key):
        phase = phases.pop(key, None)
        if phase and 'stall' in phase:
            phase['stall']['closed_after'] = round(time.time() - phase['opened'], 1)

    threading.Thread(target=watchdog, daemon=True).start()
    for line in process.stdout:
        log.write(line)
        match = TRACE.search(line)
        if not match:
            continue
        _, pid, tag, task, request, event = match.groups()
        base = (int(pid), int(tag))
        with lock:
            if request in ('spawn', 'create', 'exit'):
                key = (*base, request, request)
                if event in ('start', 'return'):
                    open_phase(key, task)
                else:
                    close_phase(key)
            elif event == 'start':
                open_phase((*base, 'call', request), task)
            elif event in ('end', 'error'):
                close_phase((*base, 'call', request))
                open_phase((*base, 'deliver', request), task)
            elif event == 'received':
                close_phase((*base, 'deliver', request))
    code = process.wait()
    log.close()
    for thread in dumps:
        thread.join(timeout=400)
    text = (OUT / f'{label}.log').read_text(encoding='utf-8')
    now = time.time()
    return {'label': label, 'exit': code, 'seconds': round(now - started, 1),
            'timeouts': text.count('TimeoutException'), 'stalls': stalls,
            'open_at_exit': [{'phase': k[2], 'request': k[3], 'task': v['task'],
                              'seconds_open': round(now - v['opened'], 1)}
                             for k, v in phases.items() if k[2] != 'spawn']}


def phase_durations():
    """Every completed phase's duration in all logs, by kind. A worker's close
    is its last call before it returns; its other calls are processing."""
    stats = collections.defaultdict(list)
    never_ended = collections.Counter()
    for path in sorted(OUT.glob('*.log')):
        opened = {}
        last_call = {}
        for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
            match = TRACE.search(line)
            if not match:
                continue
            ms, _, tag, _, request, event = match.groups()
            ms = int(ms)
            if request in ('spawn', 'create', 'exit'):
                if event in ('start', 'return'):
                    opened[(tag, request)] = ms
                elif (tag, request) in opened:
                    stats[request].append(ms - opened.pop((tag, request)))
                if request == 'exit' and event == 'return' and tag in last_call:
                    stats['close'].append(last_call.pop(tag))
            elif event == 'start':
                opened[(tag, 'call', request)] = ms
            elif event in ('end', 'error') and (tag, 'call', request) in opened:
                if tag in last_call:
                    stats['process'].append(last_call[tag])
                last_call[tag] = ms - opened.pop((tag, 'call', request))
                opened[(tag, 'deliver', request)] = ms
            elif event == 'received' and (tag, 'deliver', request) in opened:
                stats['deliver'].append(ms - opened.pop((tag, 'deliver', request)))
        stats['process'].extend(last_call.values())
        never_ended.update(key[-2] if len(key) == 3 else key[1] for key in opened)
    return {kind: {'n': len(values), 'max_ms': max(values),
                   'over_1s': sum(v > 1000 for v in values),
                   'over_5s': sum(v > 5000 for v in values),
                   'over_20s': sum(v > 20000 for v in values),
                   'never_ended': never_ended.get(
                       'call' if kind in ('process', 'close') else kind, 0)}
            for kind, values in sorted(stats.items()) if values}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if debugger('cdb.exe') is None:
        raise SystemExit('cdb.exe is not installed on this runner.')
    print(prewarm(), flush=True)
    results = []
    for mode in MODES:
        extra, files = MODE_ARGS[mode]
        for index in range(RUNS):
            result = run(f'{mode}-{index + 1}', extra, files)
            results.append(result)
            print(json.dumps(result), flush=True)
    summary = {mode: {'runs': len(rows),
                      'failed': sum(r['exit'] != 0 for r in rows),
                      'timeouts': sum(r['timeouts'] for r in rows),
                      'stalls': sum(len(r['stalls']) for r in rows),
                      'seconds': [r['seconds'] for r in rows]}
               for mode in MODES
               for rows in [[r for r in results if r['label'].startswith(mode)]]}
    report = {'summary': summary, 'phases': phase_durations(), 'runs': results}
    (OUT / 'summary.json').write_text(json.dumps(report, indent=2))
    print(json.dumps({k: report[k] for k in ('summary', 'phases')}, indent=2),
          flush=True)


if __name__ == '__main__':
    main()
