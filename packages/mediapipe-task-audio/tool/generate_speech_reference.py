"""Capture Google's Audio Transcriber and Text to Speech outputs for the tests.

Runs the official Python API from the checksum-pinned speech wheel for this
host (core's `speechReferenceWheels`: Google's 1.1.0 wheel, which the other
audio references use, has neither task), so the Dart suite on each desktop CI
runner compares against Google's own library on that runner. Never derive
expected values from the Dart implementation.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import sys

from generate_audio_reference import FIXTURES, HOST_NAMES, PACKAGE, read_clip

sys.path.insert(0, str(PACKAGE.parent / 'mediapipe-core/tool'))
from official_wheels import host_runtime  # noqa: E402
from model_pins import model_sha256  # noqa: E402

TRANSCRIBER_MODEL = 'parakeet_tdt_0.6b_v3_5s_i8_stateful.litertlm'
TTS_MODEL = 'phonon_int8.litertlm'

# Each transcriber case: the clip, the frames per block (None for one call)
# and whether interim results are on. A stream sends every block with
# end_of_stream False, then finishes the stream.
TRANSCRIBER_CASES = {
    'speech-16k': ('speech_16000_hz_mono.wav', None, False),
    'speech-48k': ('speech_48000_hz_mono.wav', None, False),
    'speech-1s-blocks': ('speech_16000_hz_mono.wav', 16000, False),
    'speech-1s-blocks-interim': ('speech_16000_hz_mono.wav', 16000, True),
}

# Each utterance: the text, the voice id and the locale (None for the
# options' defaults).
UTTERANCES = {
    'fox': ('The quick brown fox jumps over the lazy dog.', None, None),
    'claire-fr': ('Bonjour, comment allez-vous aujourd\'hui ?', 'claire', 'fr-FR'),
    'lukas-de': ('Guten Morgen, wie geht es dir?', 'lukas', 'de-DE'),
    'unicode': ('Café über naïve 😀 done.', None, None),
}
# Spoken by a task created with speaking_rate 1.5.
FAST_UTTERANCE = UTTERANCES['fox'][0]
STREAM_TEXT = 'Hello there. This is the second sentence, and it is longer. Third!'

# The envelope's window: 100 ms at Phonon's 24 kHz.
ENVELOPE_SECONDS = 0.1


def segments(result):
    return [{'transcript': s.transcript, 'is_final': s.is_final,
             'from_ms': s.from_timestamp_ms, 'to_ms': s.to_timestamp_ms}
            for s in result.segments]


def transcriber_case(model, case):
    import mediapipe as mp
    from mediapipe.tasks.python.audio import audio_transcriber

    clip, block, interim = case
    samples, rate = read_clip(clip)
    options = audio_transcriber.AudioTranscriberOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(model)),
        sample_rate_hz=rate, enable_interim_results=interim)
    with audio_transcriber.AudioTranscriber.create_from_options(options) as task:
        if block is None:
            calls = [segments(task.transcribe(samples))]
        else:
            calls = [segments(task.transcribe(samples[start:start + block],
                                              end_of_stream=False))
                     for start in range(0, len(samples), block)]
        finish = segments(task.finish_stream())
    return {'clip': clip, 'rate': rate, 'block_frames': block,
            'interim_results': interim, 'calls': calls, 'finish': finish}


def audio(result, text):
    """The parts of a synthesized result the tests compare: its length,
    rate, word timings (UTF-8 byte offsets, as Google reports them) and RMS
    per window."""
    import numpy as np

    samples = result.samples.astype(np.float64)
    window = max(1, round(result.sample_rate_hz * ENVELOPE_SECONDS))
    envelope = [round(float(np.sqrt(np.mean(samples[i:i + window] ** 2))), 6)
                for i in range(0, len(samples), window)]
    encoded = text.encode('utf-8')
    words = []
    for word in result.word_timestamps:
        assert encoded[word.start_char:word.end_char].decode('utf-8') == word.word, word
        words.append([word.word, word.start_char, word.end_char,
                      round(word.start_sec, 4), round(word.end_sec, 4)])
    return {'samples': len(samples), 'sample_rate_hz': result.sample_rate_hz,
            'peak': round(float(np.abs(samples).max(initial=0)), 6),
            'envelope': envelope, 'words': words}


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
    parser.add_argument('--output', type=Path, default=FIXTURES / 'official_speech_reference.json')
    args = parser.parse_args()
    if args.python_package_root:
        sys.path.insert(0, str(args.python_package_root.resolve()))
    os.environ.setdefault('MPLCONFIGDIR', str(PACKAGE / 'build/matplotlib'))
    import mediapipe as mp

    runtime = host_runtime('speechReferenceWheels')
    name, version = HOST_NAMES[platform.system()], runtime['version']
    assert mp.__version__ == version, mp.__version__
    library = Path(mp.__file__).parent / 'tasks/c' / runtime['library']
    assert hashlib.sha256(library.read_bytes()).hexdigest() == runtime['library_sha256']
    models = {}
    for file in (TRANSCRIBER_MODEL, TTS_MODEL):
        model = PACKAGE / 'models' / file
        models[file] = model_sha256(file)
        assert hashlib.sha256(model.read_bytes()).hexdigest() == models[file], file

    transcriber = {}
    for case, spec in TRANSCRIBER_CASES.items():
        transcriber[case] = transcriber_case(PACKAGE / 'models' / TRANSCRIBER_MODEL, spec)
        print(case, transcriber[case]['calls'][-1], transcriber[case]['finish'], flush=True)
    report = {
        'runtime': f'mediapipe=={version}',
        'source': f'official Python AudioTranscriber and TextToSpeech, {name} wheel, CPU',
        'models': models,
        'decode': '16-bit PCM WAV, samples / 32768',
        'envelope': f'RMS of each {ENVELOPE_SECONDS:g} s window, the last one partial',
        'word_offsets': 'UTF-8 byte offsets in the text, as Google reports them',
        'cases': {'transcriber': transcriber,
                  'text_to_speech': tts_reference(PACKAGE / 'models' / TTS_MODEL)},
    }
    args.output.resolve().parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=1, ensure_ascii=False) + '\n',
                           encoding='utf-8')


if __name__ == '__main__':
    main()
