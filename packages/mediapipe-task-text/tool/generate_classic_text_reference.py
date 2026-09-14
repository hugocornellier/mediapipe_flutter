"""Capture BERT, USE and language outputs from Google's pinned 1.0.1 runtime."""
import argparse
import ctypes
import dataclasses
import hashlib
import json
import os
from pathlib import Path
import platform
import sys

PACKAGE = Path(__file__).resolve().parents[1]
LIBRARY_SHA256 = '9cffc37134d98bdbbcc4b5811d2e2acd66361d05b89761e68a5cb72e0406b53a'
MODELS = {
    'classifier': ('bert_classifier.tflite', '9b45012ab143d88d61e10ea501d6c8763f7202b86fa987711519d89bfa2a88b1'),
    'embedder': ('universal_sentence_encoder.tflite', '89ad3c74175dd8caa398cc22b657296d94302d20c525c12b58b29420f7249749'),
    'language': ('language_detector.tflite', '7db4f23dfe1ad8966b050b419a865da451143fd43eb6b606a256aadeeb1e5417'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--python-package-root', required=True, type=Path)
    args = parser.parse_args()
    sys.path.insert(0, str(args.python_package_root.resolve()))
    os.environ.setdefault('MPLCONFIGDIR', str(PACKAGE / 'build/matplotlib'))
    import mediapipe as mp
    from mediapipe.tasks.python.text import text_classifier as classifier
    from mediapipe.tasks.python.text import text_embedder as embedder
    from mediapipe.tasks.python.text import language_detector as language
    from mediapipe.tasks.python.components.processors.classifier_options_c import MpClassifierOptionsC
    from mediapipe.tasks.python.components.containers.classification_result_c import MpClassificationResultC, MpClassificationsC
    from mediapipe.tasks.python.components.containers.category_c import MpCategoryC
    from mediapipe.tasks.python.components.containers.embedding_result_c import MpEmbeddingResultC, MpEmbeddingC
    assert platform.system() == 'Darwin' and platform.machine() == 'arm64'
    assert mp.__version__ == '1.0.1'
    library = Path(mp.__file__).parent / 'tasks/c/libmediapipe.dylib'
    assert hashlib.sha256(library.read_bytes()).hexdigest() == LIBRARY_SHA256
    report = {'runtime': 'mediapipe==1.0.1', 'delegate': 'CPU',
              'library_sha256': LIBRARY_SHA256, 'macos': platform.mac_ver()[0],
              'models': {}, 'cases': [], 'creation_errors': [], 'lifecycle_sequences': {}}
    for name, (file, sha) in MODELS.items():
        model = PACKAGE / 'example/assets' / file
        assert hashlib.sha256(model.read_bytes()).hexdigest() == sha
        report['models'][name] = {'file': file, 'sha256': sha}
    specs = [
        ('classifier', classifier.TextClassifierOptions, classifier.TextClassifier, 'classify', [
            ('positive', 'Hello, world!', {}),
            ('negative', 'This was a terrible movie. I hated every minute.', {}),
            ('unicode', 'The café was wonderful — I loved it!', {}),
            ('empty', '', {}),
            ('allow', 'Hello, world!', {'category_allowlist': ['positive', 'unknown', 'positive']}),
            ('deny', 'Hello, world!', {'category_denylist': ['positive']}),
            ('top', 'Hello, world!', {'max_results': 1}),
            ('threshold', 'Hello, world!', {'score_threshold': 1.0}),
            ('locale', 'Hello, world!', {'display_names_locale': 'fr'}),
        ]),
        ('embedder', embedder.TextEmbedderOptions, embedder.TextEmbedder, 'embed', [
            ('greeting', 'Hello, world!', {}),
            ('related', 'Hello there!', {}),
            ('different', 'The spacecraft landed on Mars.', {}),
            ('unicode', 'Le café est délicieux. こんにちは', {}),
            ('empty', '', {}),
            ('normalized', 'Hello, world!', {'l2_normalize': True}),
            ('quantized', 'Hello, world!', {'l2_normalize': True, 'quantize': True}),
            ('quantized-related', 'Hello there!', {'l2_normalize': True, 'quantize': True}),
        ]),
        ('language', language.LanguageDetectorOptions, language.LanguageDetector, 'detect', [
            ('english', 'Hello, world!', {}),
            ('spanish', 'Quiero agua, por favor.', {}),
            ('japanese', 'こんにちは、元気ですか？', {}),
            ('french', 'Bonjour, comment allez-vous aujourd’hui ?', {}),
            ('empty', '', {}),
            ('top', 'Hello, world!', {'max_results': 2}),
            ('allow', 'Hello, world!', {'category_allowlist': ['en', 'fr']}),
            ('deny', 'Hello, world!', {'category_denylist': ['en'], 'max_results': 2}),
            ('threshold', 'Hello, world!', {'score_threshold': 1.0}),
        ]),
    ]
    embeddings = {}
    def result_json(result, task_name):
        if task_name != 'embedder':
            return dataclasses.asdict(result)
        return {'timestamp_ms': result.timestamp_ms, 'embeddings': [
            {'values': e.embedding.tolist(), 'quantized': e.embedding.dtype.name == 'uint8',
             'head_index': e.head_index, 'head_name': e.head_name} for e in result.embeddings]}

    for task_name, options_class, task_class, method, cases in specs:
        model = PACKAGE / 'example/assets' / MODELS[task_name][0]
        for name, text, config in cases:
            with task_class.create_from_options(options_class(
                    mp.tasks.BaseOptions(model_asset_path=str(model)), **config)) as task:
                result = getattr(task, method)(text)
                if task_name == 'embedder':
                    embeddings[name] = result.embeddings[0]
                value = result_json(result, task_name)
                report['cases'].append({'task': task_name, 'name': name, 'input': text,
                                        'options': config, 'result': value})
                print(task_name, name, flush=True)
        with task_class.create_from_options(options_class(
                mp.tasks.BaseOptions(model_asset_path=str(model)))) as task:
            report['lifecycle_sequences'][task_name] = [
                {'input': text, 'result': result_json(getattr(task, method)(text), task_name)}
                for text in ['Hello, world!', 'Quiero agua, por favor.'] * 2]
        if task_name != 'embedder':
            for config in ({'max_results': 0}, {'category_allowlist': ['en'], 'category_denylist': ['fr']}):
                try:
                    with task_class.create_from_options(options_class(
                            mp.tasks.BaseOptions(model_asset_path=str(model)), **config)):
                        raise AssertionError('Expected creation to fail')
                except ValueError as error:
                    report['creation_errors'].append({'task': task_name, 'options': config, 'error': str(error)})
    report['similarities'] = [{'a': a, 'b': b, 'value': embedder.TextEmbedder.cosine_similarity(embeddings[a], embeddings[b])}
                              for a, b in [('greeting', 'greeting'), ('greeting', 'related'), ('greeting', 'different'),
                                           ('quantized', 'quantized-related')]]
    report['abi'] = {cls.__name__: {
        'size': ctypes.sizeof(cls), 'alignment': ctypes.alignment(cls),
        'offsets': {f[0]: getattr(cls, f[0]).offset for f in cls._fields_}}
        for cls in (classifier.MpTextClassifierOptionsC, MpClassifierOptionsC, MpClassificationResultC,
                    MpClassificationsC, MpCategoryC, MpEmbeddingResultC, MpEmbeddingC,
                    language.MpLanguageDetectorOptionsC, language.MpLanguageDetectorPredictionC,
                    language.MpLanguageDetectorResultC)}
    target = PACKAGE / 'test/fixtures/classic_text/official_reference.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    main()
