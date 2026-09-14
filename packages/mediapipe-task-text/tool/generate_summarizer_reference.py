"""Capture official macOS CPU Summarizer results, streams and ctypes layouts."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import platform
import sys
import threading
import time

PACKAGE = Path(__file__).resolve().parents[1]
MODEL_SHA256 = '8b2d4ef09236adb9ead3127325526ba1aa5a59feb7c5de2d3f5958f27479de59'
LIBRARY_SHA256 = '9cffc37134d98bdbbcc4b5811d2e2acd66361d05b89761e68a5cb72e0406b53a'
MODEL_URL = 'https://storage.googleapis.com/mediapipe-models/text_summarizer/200m/1/summarization_quant_200m_2modes.litertlm'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--python-package-root', required=True, type=Path)
    args = parser.parse_args()
    sys.path.insert(0, str(args.python_package_root.resolve()))
    os.environ.setdefault('MPLCONFIGDIR', str(PACKAGE / 'build/matplotlib'))
    import mediapipe as mp
    from mediapipe.tasks.python.text import text_summarizer as api
    from mediapipe.tasks.python.core.base_options_c import MpBaseOptionsC
    assert platform.system() == 'Darwin' and platform.machine() == 'arm64'
    assert mp.__version__ == '1.0.1'
    library = Path(mp.__file__).parent / 'tasks/c/libmediapipe.dylib'
    assert hashlib.sha256(library.read_bytes()).hexdigest() == LIBRARY_SHA256
    model = PACKAGE / 'models/summarization_quant_200m_2modes.litertlm'
    assert hashlib.sha256(model.read_bytes()).hexdigest() == MODEL_SHA256
    cases = [
        ('meeting', 'The team met on Monday to plan the next app release. Maya will finish '
         'the camera interface by Thursday. Leo will investigate the startup crash and '
         'send a fix for review on Wednesday. Testing begins on Friday, and the release '
         'is scheduled for the following Tuesday if no critical bugs remain. The team '
         'decided to postpone the new settings screen until the next release.'),
        ('garden', 'A community garden opened beside the town library in April. Volunteers '
         'built twelve raised beds and planted tomatoes, carrots, and herbs. Rainwater '
         'collected from the library roof supplies most of the irrigation. Residents '
         'can join a Saturday workshop to learn composting and share tools. Half of '
         'the vegetables harvested this summer will be donated to the local food bank.'),
        ('unicode', 'María and André opened a café in Montréal last spring. They serve '
         'coffee and fresh pastries every morning. After customers requested more '
         'options, they added vegan sandwiches and extended their opening hours on '
         'weekends. They plan to hire two employees before the winter season.'),
        ('short', 'The library will close at six today for maintenance and reopen tomorrow morning.'),
        ('empty', ''),
    ]
    report = {'runtime': 'mediapipe==1.0.1', 'delegate': 'CPU',
              'library_sha256': LIBRARY_SHA256, 'model_sha256': MODEL_SHA256,
              'model_url': MODEL_URL, 'macos': platform.mac_ver()[0], 'cases': [], 'errors': []}
    for mode in api.Mode:
        for limit in [None, 64]:
            options = api.TextSummarizerOptions(mp.tasks.BaseOptions(
                model_asset_path=str(model), delegate=mp.tasks.BaseOptions.Delegate.CPU),
                mode=mode, max_num_tokens=limit)
            with api.TextSummarizer.create_from_options(options) as task:
                for name, text in (cases if limit is None else cases[3:4]):
                    start = time.perf_counter()
                    try:
                        result = task.summarize(text)
                    except ValueError as error:
                        assert text == '', f'Unexpected failure: {error}'
                        terminal = threading.Event()
                        errors = []
                        def error_callback(update, message):
                            errors.append(message)
                            terminal.set()
                        try:
                            task.summarize_async(text, error_callback)
                        except ValueError as stream_error:
                            errors.append(str(stream_error))
                        else:
                            assert terminal.wait(60), 'No empty-input error callback'
                        assert errors == [str(error)], errors
                        report['errors'].append({'input': text, 'mode': mode.name,
                            'message': str(error), 'stream_message': errors[0]})
                        print(mode.name, 'empty input rejected:', error, flush=True)
                        continue
                    sync_ms = (time.perf_counter() - start) * 1000
                    events = []
                    done = threading.Event()
                    def callback(update, error):
                        events.append({'error': error} if error else
                                      {'chunk': update.summary, 'done': update.done})
                        if error or update.done: done.set()
                    start = time.perf_counter()
                    task.summarize_async(text, callback)
                    assert done.wait(60), 'No terminal callback'
                    stream_ms = (time.perf_counter() - start) * 1000
                    assert not any('error' in event for event in events), events
                    assert sum(e['done'] for e in events) == 1 and events[-1]['done']
                    assert ''.join(e['chunk'] or '' for e in events) == (result.summary or '')
                    report['cases'].append({
                        'name': f'{mode.name.lower()}-{name}' + (f'-limit-{limit}' if limit else ''),
                        'input': text, 'mode': mode.name, 'max_num_tokens': limit,
                        'result': {'summary': result.summary, 'done': result.done},
                        'stream': events, 'sync_ms': sync_ms, 'stream_ms': stream_ms})
                    print(mode.name, name, limit, round(sync_ms, 2), repr(result.summary), flush=True)
    report['abi'] = {cls.__name__: {
        'size': ctypes.sizeof(cls), 'alignment': ctypes.alignment(cls),
        'offsets': {f[0]: getattr(cls, f[0]).offset for f in cls._fields_}}
        for cls in (MpBaseOptionsC, api._MpTextSummarizerOptionsC,
                    api._MpTextSummarizerResultC, api._MpTextSummarizerStreamResultC)}
    (PACKAGE / 'test/fixtures/summarizer/official_reference.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
