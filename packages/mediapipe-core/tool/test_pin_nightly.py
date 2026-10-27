"""Unit tests for the nightly pin, offline:
python3 -B -m unittest packages/mediapipe-core/tool/test_pin_nightly.py"""
from pathlib import Path
import re
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pin_nightly  # noqa: E402


def pinned_digests(source):
    """`{path: (sha256, size)}` as `familyRuntimes` pins them."""
    return {path: (sha256, int(size)) for path, sha256, size in re.findall(
        r"FamilyRuntime\(\s*'([^']+)',\s*'([0-9a-f]{64})',\s*(\d+),\s*\)", source)}


class PinNightlyTest(unittest.TestCase):
    def setUp(self):
        self.source = pin_nightly.FAMILY_RUNTIMES.read_text(encoding='utf-8')
        self.relative = str(pin_nightly.FAMILY_RUNTIMES.relative_to(pin_nightly.REPO))
        self.old = pin_nightly.current_pins()
        self.digests = pinned_digests(self.source)

    def rewrite(self, old, generation):
        return pin_nightly.rewritten_sources(
            old, old['stamp'], old['version'], generation, self.digests)

    def test_reads_every_pin(self):
        self.assertEqual(len(self.old['paths']), 40)
        self.assertEqual(set(self.old['paths']), set(self.digests))

    def test_the_same_build_rewrites_nothing(self):
        for relative, text in self.rewrite(self.old, None).items():
            self.assertEqual(text, (pin_nightly.REPO / relative).read_text(encoding='utf-8'),
                             relative)

    def test_a_generation_goes_on_its_own_line_and_comes_off_again(self):
        pinned = self.rewrite(self.old, '1792585037995595')[self.relative]
        stamp = self.old['stamp']
        self.assertIn(f"    'mediapipe_tasks_c/{stamp}/mediapipe_tasks_c_{stamp}.zip'\n"
                      "    '?generation=1792585037995595';\n", pinned)
        self.assertEqual(len(pinned.splitlines()), len(self.source.splitlines()) + 1)
        with tempfile.TemporaryDirectory() as directory:
            copy = Path(directory, 'family_runtimes.dart')
            copy.write_text(pinned, encoding='utf-8')
            original, pin_nightly.FAMILY_RUNTIMES = pin_nightly.FAMILY_RUNTIMES, copy
            try:
                old = pin_nightly.current_pins()
            finally:
                pin_nightly.FAMILY_RUNTIMES = original
        self.assertEqual(old['generation'], '1792585037995595')
        self.assertEqual(self.old['generation'], None)
        # rewritten_sources reads the repository's files; give it the
        # generation-pinned one by its text.
        before = pin_nightly.render(pin_nightly.SENTENCES[self.relative][3],
                                    stamp, old['version'], old['generation'])
        after = pin_nightly.render(pin_nightly.SENTENCES[self.relative][3],
                                   stamp, old['version'])
        self.assertEqual(pinned.replace(before, after), self.source)

    def test_comments_are_not_the_api(self):
        header = '// Source revision: 1\nint mp_open(const char* path); /* a */\n'
        comments_moved = '// Source revision: 2\nint mp_open(const char* path);\n/* b */\n'
        self.assertEqual(pin_nightly.strip_comments(header),
                         pin_nightly.strip_comments(comments_moved))
        self.assertNotEqual(pin_nightly.strip_comments(header),
                            pin_nightly.strip_comments(header.replace('path', 'path, int n')))


FIXTURES = Path(__file__).resolve().parent / 'fixtures/nightly_headers'


def nightly_headers(stamp):
    """Google's headers of nightly `stamp`, as pin_nightly merges them:
    `native/include` with the headers that differ between the fixture
    nightlies (20261018, 20261021, 20261023) as `stamp` has them, so a later
    pin of `native/include` leaves these tests as they are."""
    varied = {str(path.relative_to(folder)) for folder in FIXTURES.iterdir()
              for path in folder.rglob('*') if path.is_file()}
    merged = {str(path.relative_to(pin_nightly.HEADERS)): path.read_bytes()
              for path in pin_nightly.HEADERS.rglob('*') if path.is_file()}
    merged = {name: data for name, data in merged.items() if name not in varied}
    merged.update({str(path.relative_to(FIXTURES / stamp)): path.read_bytes()
                   for path in (FIXTURES / stamp).rglob('*') if path.is_file()})
    return merged


class HeaderDecisionTest(unittest.TestCase):
    """What a nightly's header changes stop, on Google's real headers."""

    def setUp(self):
        self.october_18 = nightly_headers('20261018')
        self.tasks = sorted({pin_nightly.task_of(name) for name in self.october_18} - {None})

    def test_the_pinned_build_has_22_tasks(self):
        self.assertEqual(len(self.tasks), 22)
        self.assertIn('semantic_retriever', self.tasks)
        self.assertIn('interactive_segmenter_legacy', self.tasks)

    def test_october_21_runs_every_task(self):
        verdict = pin_nightly.classify_headers(self.october_18, nightly_headers('20261021'))
        self.assertEqual(verdict['changes'], [])
        self.assertEqual(verdict['blocking'], [])
        self.assertEqual(verdict['skipped'], {})
        self.assertEqual(verdict['new_tasks'], [])
        # Only the umbrellas' "Source revision" comments moved.
        self.assertEqual(verdict['comment_only'], [
            f'mediapipe_tasks_{family}.h'
            for family in ('audio', 'decision', 'retrieval', 'text', 'vision')])

    def test_october_23_leaves_out_the_semantic_retriever_alone(self):
        verdict = pin_nightly.classify_headers(self.october_18, nightly_headers('20261023'))
        # Every change it holds, which once stopped every suite.
        self.assertEqual(verdict['changes'], [
            'added audio/audio_transcriber/audio_transcriber.h',
            'added audio/text_to_speech/text_to_speech.h',
            'changed mediapipe_tasks_audio.h',
            'changed retrieval/semantic_retriever/semantic_retriever.h',
        ])
        self.assertEqual(verdict['blocking'], [])
        self.assertEqual(verdict['skipped'], {'semantic_retriever': [
            'changed retrieval/semantic_retriever/semantic_retriever.h']})
        self.assertEqual(verdict['new_tasks'], ['audio_transcriber', 'text_to_speech'])
        run = [task for task in self.tasks if task not in verdict['skipped']]
        self.assertEqual(len(run), 21)
        # The audio_classifier.h license typo fix is a comment.
        self.assertIn('audio/audio_classifier/audio_classifier.h', verdict['comment_only'])

    def test_what_still_stops_every_suite(self):
        old = self.october_18
        status = old['core/mp_status.h'].decode('utf-8')
        for name, new in {
            'core/mp_status.h': dict(old, **{'core/mp_status.h':
                                             (status + '\nint mp_new(void);\n').encode()}),
            'vision/face_detector/face_detector.h': dict(
                old, **{'vision/face_detector/face_detector.h': b'int changed(void);\n'}),
            'mediapipe_tasks_text.h': dict(
                old, **{'mediapipe_tasks_text.h':
                        old['mediapipe_tasks_text.h'] + b'\nint declared_here(void);\n'}),
        }.items():
            verdict = pin_nightly.classify_headers(old, new)
            self.assertEqual(len(verdict['blocking']), 1, name)
            self.assertTrue(verdict['blocking'][0].startswith(f'changed {name}: '), name)
        removed = {name: data for name, data in old.items() if name != 'core/common.h'}
        self.assertEqual(pin_nightly.classify_headers(old, removed)['blocking'],
                         ['removed core/common.h: shared by every task'])

    def test_the_universal_embedder_takes_the_semantic_retriever_with_it(self):
        name = 'retrieval/universal_embedder/universal_embedder.h'
        new = dict(self.october_18, **{name: self.october_18[name] + b'\nint x(void);\n'})
        self.assertEqual(sorted(pin_nightly.classify_headers(self.october_18, new)['skipped']),
                         ['semantic_retriever', 'universal_embedder'])


if __name__ == '__main__':
    unittest.main()
