"""Capture official macOS CPU Proofreader results, streams and ctypes layouts."""
import argparse
import ctypes
import dataclasses
import hashlib
import json
import os
from pathlib import Path
import platform
import sys
import threading
import time

PACKAGE = Path(__file__).resolve().parents[1]
MODEL_SHA256 = '2caa317d5a6f951af6e437edce3bb3a9fdedc85a7a8c2a8fcaec96318d7708cc'
LIBRARY_SHA256 = '9cffc37134d98bdbbcc4b5811d2e2acd66361d05b89761e68a5cb72e0406b53a'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--python-package-root', required=True, type=Path)
    args = parser.parse_args()
    sys.path.insert(0, str(args.python_package_root.resolve()))
    os.environ.setdefault('MPLCONFIGDIR', str(PACKAGE / 'build/matplotlib'))
    import mediapipe as mp
    from mediapipe.tasks.python.text import text_proofreader as api
    from mediapipe.tasks.python.core.base_options_c import MpBaseOptionsC
    assert platform.system() == 'Darwin' and platform.machine() == 'arm64'
    assert mp.__version__ == '1.0.1'
    library = Path(mp.__file__).parent / 'tasks/c/libmediapipe.dylib'
    assert hashlib.sha256(library.read_bytes()).hexdigest() == LIBRARY_SHA256
    model = PACKAGE / 'models/proofread_quant_200m.litertlm'
    assert hashlib.sha256(model.read_bytes()).hexdigest() == MODEL_SHA256
    cases = [
        ('grammar', 'She go to the store yesterday and buyed some apples.'),
        ('spelling', 'I recieved your mesage and will reply tomorow.'),
        ('unchanged', 'The cat is sleeping on the sofa.'),
        ('punctuation', 'hello my name is sam i live in canada'),
        ('unicode', 'The café serve delicious croissants, and María enjoy them.'),
        ('empty', ''),
        ('paragraph', 'Our team have finished the first version of the app. We was testing it '
         'yesterday when we notice a small problem. The report explain how to reproduce the '
         'issue, and include a screenshot. Please let me knows if you needs any more details.'),
    ]
    report = {'runtime': 'mediapipe==1.0.1', 'delegate': 'CPU',
              'library_sha256': LIBRARY_SHA256, 'model_sha256': MODEL_SHA256,
              'model_url': 'https://storage.googleapis.com/mediapipe-models/text_proofreader/200m/1/proofread_quant_200m.litertlm',
              'macos': platform.mac_ver()[0], 'cases': []}

    def result_json(result):
        return {'text': result.proofread_text, 'done': result.done,
                'corrections': [{'type': c.type.name.lower(), 'text': c.text} for c in result.corrections]}

    for limit in [None, 64]:
        options = api.TextProofreaderOptions(mp.tasks.BaseOptions(
            model_asset_path=str(model), delegate=mp.tasks.BaseOptions.Delegate.CPU),
            max_num_tokens=limit)
        with api.TextProofreader.create_from_options(options) as task:
            for name, text in (cases if limit is None else cases[:2]):
                start = time.perf_counter()
                sync = result_json(task.proofread(text))
                sync_ms = (time.perf_counter() - start) * 1000
                events = []
                done = threading.Event()
                def callback(result, error):
                    events.append({'error': error} if error else result_json(result))
                    if error or result.done: done.set()
                start = time.perf_counter()
                task.proofread_async(text, callback)
                assert done.wait(60), 'No terminal callback'
                stream_ms = (time.perf_counter() - start) * 1000
                assert not any('error' in event for event in events), events
                assert sum(e['done'] for e in events) == 1 and events[-1]['done']
                assert ''.join(e['text'] or '' for e in events) == (sync['text'] or '')
                assert events[-1]['corrections'] == sync['corrections']
                report['cases'].append({'name': name + (f'-limit-{limit}' if limit else ''),
                    'input': text, 'max_num_tokens': limit, 'result': sync,
                    'stream': events, 'sync_ms': sync_ms, 'stream_ms': stream_ms})
                print(name, limit, round(sync_ms, 2), sync['text'], flush=True)
    report['abi'] = {cls.__name__: {
        'size': ctypes.sizeof(cls), 'alignment': ctypes.alignment(cls),
        'offsets': {f[0]: getattr(cls, f[0]).offset for f in cls._fields_}}
        for cls in (MpBaseOptionsC, api._MpTextProofreaderOptionsC, api._MpCorrectionC,
                    api._MpTextProofreaderResultC, api._MpTextProofreaderStreamResultC)}
    (PACKAGE / 'test/fixtures/proofreader/official_reference.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
