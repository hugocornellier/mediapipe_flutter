"""Unit tests for the nightly pin, offline:
python3 -B -m unittest packages/mediapipe-core/tool/test_pin_nightly.py"""
import http.client
import io
import json
from pathlib import Path
import re
import sys
import tempfile
import types
import unittest
from unittest import mock
import urllib.error

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pin_nightly  # noqa: E402


def pinned_digests(source):
    """`{path: (sha256, size)}` as `familyRuntimes` pins them."""
    return {path: (sha256, int(size)) for path, sha256, size in re.findall(
        r"FamilyRuntime\(\s*'([^']+)',\s*'([0-9a-f]{64})',\s*(\d+),\s*\)", source)}


class Bucket:
    """Stands in for Fetcher: `{stamp: version}`, None for a folder with no
    BUILD_INFO."""

    def __init__(self, builds):
        self.builds = builds

    def json(self, _):
        return {'prefixes': [f'{pin_nightly.PREFIX}{name}/' for name in [*self.builds, '1.2.1']]}

    def text(self, url):
        version = self.builds[url.split('/')[-2]]
        return version and f'build_date=x\nmediapipe_version={version}\n'


class VersionStopTest(unittest.TestCase):
    def since(self, builds, stamp='20261106', version='1.2.0'):
        return pin_nightly.version_stop_since(Bucket(builds), stamp, version, '20261018')

    def test_starts_at_the_first_build_after_the_pinned_version(self):
        self.assertEqual(self.since({'20261029': '1.2.0', '20261030': '1.2.1',
                                     '20261105': '1.2.2', '20261106': '1.2.2'}), '20261030')

    def test_only_the_run_ending_at_the_picked_build_counts(self):
        self.assertEqual(self.since({'20261001': '1.2.2', '20261002': '1.2.0',
                                     '20261105': '1.2.2', '20261106': '1.2.2'}), '20261105')

    def test_a_newer_build_that_was_not_picked_is_left_out(self):
        self.assertEqual(self.since({'20261104': '1.2.0', '20261105': '1.2.2',
                                     '20261106': '1.2.2', '20261107': '1.2.0'}), '20261105')

    def test_a_folder_with_no_build_info_is_passed_over(self):
        self.assertEqual(self.since({'20261029': '1.2.0', '20261030': '1.2.1',
                                     '20261031': None, '20261106': '1.2.2'}), '20261030')
        self.assertEqual(self.since({'20261029': '1.2.0', '20261030': None,
                                     '20261031': '1.2.1', '20261106': '1.2.2'}), '20261031')

    def test_with_the_pinned_version_pruned_it_starts_at_the_pinned_build(self):
        self.assertEqual(self.since({'20261030': '1.2.1', '20261106': '1.2.2'}), '20261018')

    def stop_in_report(self, **since):
        """main's version_stop, its failure's text alongside."""
        old = pin_nightly.current_pins()
        info = f"build_date=20261106\nmediapipe_version={old['version']}.new\n"
        archive = types.SimpleNamespace(url='u', generation='1', size=1)
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory, 'report.json')
            argv = ['pin_nightly.py', '--nightly', 'newest', '--report', str(report)]
            with mock.patch.object(sys, 'argv', argv), \
                    mock.patch.object(pin_nightly, 'pick_build',
                                      return_value=('20261106', info, archive)), \
                    mock.patch.object(pin_nightly, 'version_stop_since', **since), \
                    mock.patch('sys.stdout', io.StringIO()), \
                    self.assertRaises(SystemExit) as caught:
                pin_nightly.main()
            stop = json.loads(report.read_text(encoding='utf-8'))['version_stop']
        self.assertEqual((stop['version'], stop['pinned']),
                         (f"{old['version']}.new", old['version']))
        return stop['since'], str(caught.exception)

    def test_the_report_dates_the_stop_and_the_exit_stays_nonzero(self):
        since, failure = self.stop_in_report(return_value='20261030')
        self.assertEqual(since, '20261030')
        self.assertIn('move it by hand', failure)

    def test_a_network_failure_leaves_the_date_unknown(self):
        for error in (urllib.error.URLError('no route'), TimeoutError(), ConnectionResetError(),
                      urllib.error.HTTPError('u', 503, 'down', None, None),
                      http.client.IncompleteRead(b''), json.JSONDecodeError('bad', '', 0)):
            since, failure = self.stop_in_report(side_effect=error)
            self.assertIsNone(since, error)
            self.assertIn('move it by hand', failure)


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


if __name__ == '__main__':
    unittest.main()
