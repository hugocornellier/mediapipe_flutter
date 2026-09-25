"""Capture Google's Audio Classifier outputs for the test clips.

Runs the official Python API from the checksum-pinned wheel for this host, so
the Dart suite on each desktop CI runner compares against Google's own library
on that runner. Never derive expected values from the Dart implementation.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import sys
import wave

PACKAGE = Path(__file__).resolve().parents[1]
FIXTURES = PACKAGE / 'test/fixtures'
CLIPS = ['speech_16000_hz_mono.wav', 'speech_48000_hz_mono.wav', 'two_heads_16000_hz_mono.wav']
MODEL_SHA256 = '4d8b4a53282dc83ef04e3e7dbc4fbc98082e34e44ed798e16c3a0cdd4c584faf'
sys.path.insert(0, str(PACKAGE.parent / 'mediapipe-core/tool'))
from official_wheels import host_runtime  # noqa: E402
HOST_NAMES = {'Darwin': 'macOS arm64', 'Linux': 'Linux x64', 'Windows': 'Windows x64'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--python-package-root', type=Path, help='Extracted official wheel')
    parser.add_argument('--output', type=Path, default=FIXTURES / 'official_reference.json')
    args = parser.parse_args()
    if args.python_package_root:
        sys.path.insert(0, str(args.python_package_root.resolve()))
    os.environ.setdefault('MPLCONFIGDIR', str(PACKAGE / 'build/matplotlib'))
    import numpy as np
    import mediapipe as mp
    from mediapipe.tasks.python import audio
    from mediapipe.tasks.python.components.containers import audio_data

    runtime = host_runtime()
    name, version = HOST_NAMES[platform.system()], runtime['version']
    assert mp.__version__ == version, mp.__version__
    library = Path(mp.__file__).parent / 'tasks/c' / runtime['library']
    assert hashlib.sha256(library.read_bytes()).hexdigest() == runtime['library_sha256']
    model = PACKAGE / 'models/yamnet.tflite'
    assert hashlib.sha256(model.read_bytes()).hexdigest() == MODEL_SHA256

    report = {
        'runtime': f'mediapipe=={version}',
        'source': f'official Python AudioClassifier, {name} wheel, max_results 3',
        'model': model.name,
        'model_sha256': MODEL_SHA256,
        'decode': '16-bit PCM WAV, samples / 32768',
        'clips': {},
    }
    options = audio.AudioClassifierOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(model)), max_results=3)
    with audio.AudioClassifier.create_from_options(options) as classifier:
        for clip in CLIPS:
            with wave.open(str(FIXTURES / clip), 'rb') as source:
                assert source.getsampwidth() == 2 and source.getnchannels() == 1
                rate = source.getframerate()
                frames = source.readframes(source.getnframes())
            samples = np.frombuffer(frames, dtype='<i2').astype(np.float32) / 32768
            results = classifier.classify(audio_data.AudioData.create_from_array(samples, rate))
            report['clips'][clip] = [
                {'timestamp_ms': result.timestamp_ms,
                 'top': [[category.category_name, round(category.score, 6)]
                         for category in result.classifications[0].categories]}
                for result in results]
            print(clip, len(results), flush=True)
    args.output.resolve().parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=1) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
