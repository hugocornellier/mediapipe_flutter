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
            old, {**old, 'generation': generation}, self.digests)

    def test_reads_every_pin(self):
        self.assertEqual(len(self.old['paths']), 40)
        self.assertEqual(set(self.old['paths']), set(self.digests))

    def test_the_same_build_rewrites_nothing(self):
        for relative, text in self.rewrite(self.old, None).items():
            self.assertEqual(text, (pin_nightly.REPO / relative).read_text(encoding='utf-8'),
                             relative)

    def test_a_generation_goes_on_its_own_line_and_comes_off_again(self):
        pinned = self.rewrite(self.old, '1792585037995595')[self.relative]
        folder = self.old['folder']
        self.assertIn(f"    'mediapipe_tasks_c/{folder}/mediapipe_tasks_c_{folder}.zip'\n"
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
        before = pin_nightly.render(pin_nightly.SENTENCES[self.relative][3], old)
        after = pin_nightly.render(pin_nightly.SENTENCES[self.relative][3],
                                   {**old, 'generation': None})
        self.assertEqual(pinned.replace(before, after), self.source)

    def test_a_release_and_a_nightly_render_their_own_names(self):
        release = {'folder': '1.2.2', 'stamp': '20261102', 'version': '1.2.2'}
        nightly = {'folder': '20261103', 'stamp': '20261103', 'version': '1.2.2'}
        templates = pin_nightly.SENTENCES[self.relative]
        self.assertEqual(pin_nightly.render(templates[0], release),
                         'libraries: the 1.2.2 release build of November 2, 2026.')
        self.assertEqual(pin_nightly.render(templates[1], release),
                         "const familyRuntimeVersion = '1.2.2';")
        self.assertEqual(pin_nightly.render(templates[3], release),
                         "    'mediapipe_tasks_c/1.2.2/mediapipe_tasks_c_1.2.2.zip';")
        self.assertEqual(pin_nightly.render(templates[1], nightly),
                         "const familyRuntimeVersion = '1.2.2-nightly.20261103';")
        self.assertEqual(pin_nightly.render(templates[0], nightly),
                         'libraries: the 1.2.2 nightly build of November 3, 2026.')

    def test_the_pin_round_trips_through_its_sentences(self):
        # Moving to another build and back restores every file.
        other = ({'folder': '20261103', 'stamp': '20261103', 'version': '1.2.2'}
                 if pin_nightly.is_release(self.old['folder']) else
                 {'folder': '9.9.9', 'stamp': '20991231', 'version': '9.9.9'})
        moved = pin_nightly.rewritten_sources(self.old, other, self.digests)
        for relative, text in moved.items():
            for template in pin_nightly.SENTENCES[relative]:
                self.assertIn(pin_nightly.render(template, other), text, relative)

    def test_comments_are_not_the_api(self):
        header = '// Source revision: 1\nint mp_open(const char* path); /* a */\n'
        comments_moved = '// Source revision: 2\nint mp_open(const char* path);\n/* b */\n'
        self.assertEqual(pin_nightly.strip_comments(header),
                         pin_nightly.strip_comments(comments_moved))
        self.assertNotEqual(pin_nightly.strip_comments(header),
                            pin_nightly.strip_comments(header.replace('path', 'path, int n')))


if __name__ == '__main__':
    unittest.main()
