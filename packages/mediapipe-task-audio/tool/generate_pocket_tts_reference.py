"""Capture Google's Text to Speech outputs for Kyutai's PocketTTS English.

Runs the official Python API from the checksum-pinned speech wheel for this
host, as generate_speech_reference.py does for Phonon, on
`AudioModels.pocketTtsEn`: its voices, an utterance in the default voice and
in a second one, the same utterance at speaking rate 1.5, and a stream. Never
derive expected values from the Dart implementation.
"""
import argparse
import hashlib
import os
from pathlib import Path
import platform
import sys

from generate_audio_reference import FIXTURES, HOST_NAMES, PACKAGE
from generate_speech_reference import ENVELOPE_SECONDS, STREAM_TEXT, audio

sys.path.insert(0, str(PACKAGE.parent / 'mediapipe-core/tool'))
from official_wheels import host_runtime  # noqa: E402
from model_pins import model_sha256  # noqa: E402
from tool_helpers import reference_json  # noqa: E402

MODEL = 'pocket_tts_en_int8.litertlm'

# Each utterance: the text, the voice id and the locale (None for the
# options' defaults, which name alba).
UTTERANCES = {
    'fox': ('The quick brown fox jumps over the lazy dog.', None, None),
    'marius': ('Good morning, how are you today?', 'marius', None),
}
# Spoken by a task created with speaking_rate 1.5.
FAST_UTTERANCE = UTTERANCES['fox'][0]


def tts_reference(model):
    import mediapipe as mp
    from mediapipe.tasks.python.audio import text_to_speech

    def create(**options):
        return text_to_speech.TextToSpeech.create_from_options(
            text_to_speech.TextToSpeechOptions(
                base_options=mp.tasks.BaseOptions(model_asset_path=str(model)), **options))

    with create() as task:
        voices = [{'voice_id': v.voice_id, 'display_name': v.display_name,
                   'locale': v.locale, 'sample_rate_hz': v.sample_rate_hz,
                   'is_downloaded': v.is_downloaded} for v in task.list_voices()]
        utterances = {}
        for name, (text, voice, locale) in UTTERANCES.items():
            utterances[name] = {'text': text, 'voice_id': voice, 'locale': locale,
                                **audio(task.synthesize(text, voice_id=voice, locale=locale),
                                        text)}
            print(name, utterances[name]['samples'], 'samples', flush=True)
        chunks = [{'chunk_index': chunk.chunk_index, 'is_final': chunk.is_final,
                   **audio(chunk, STREAM_TEXT)}
                  for chunk in task.synthesize_stream(STREAM_TEXT)]
        print('stream', len(chunks), 'chunks', flush=True)
    with create(speaking_rate=1.5) as task:
        fast = {'text': FAST_UTTERANCE, 'speaking_rate': 1.5,
                **audio(task.synthesize(FAST_UTTERANCE), FAST_UTTERANCE)}
    return {'voices': voices, 'utterances': utterances, 'fast': fast,
            'stream': {'text': STREAM_TEXT, 'chunks': chunks}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--python-package-root', type=Path, help='Extracted official wheel')
    parser.add_argument('--output', type=Path,
                        default=FIXTURES / 'official_pocket_tts_reference.json')
    args = parser.parse_args()
    if args.python_package_root:
        sys.path.insert(0, str(args.python_package_root.resolve()))
    os.environ.setdefault('MPLCONFIGDIR', str(PACKAGE / 'build/matplotlib'))
    import mediapipe as mp

    runtime = host_runtime('releaseReferenceWheels')
    name, version = HOST_NAMES[platform.system()], runtime['version']
    assert mp.__version__ == version, mp.__version__
    library = Path(mp.__file__).parent / 'tasks/c' / runtime['library']
    assert hashlib.sha256(library.read_bytes()).hexdigest() == runtime['library_sha256']
    model = PACKAGE / 'models' / MODEL
    models = {MODEL: model_sha256(MODEL)}
    assert hashlib.sha256(model.read_bytes()).hexdigest() == models[MODEL], MODEL

    report = {
        'runtime': f'mediapipe=={version}',
        'source': f'official Python TextToSpeech, {name} wheel, CPU',
        'models': models,
        'envelope': f'RMS of each {ENVELOPE_SECONDS:g} s window, the last one partial',
        'word_offsets': 'UTF-8 byte offsets in the text, as Google reports them',
        'cases': {'text_to_speech': tts_reference(model)},
    }
    args.output.resolve().parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(reference_json(report, ensure_ascii=False) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
