"""Unit tests for the release suite runner: python3 -B -m unittest tool/ci/test_run_release_suite.py"""
import io
import os
from pathlib import Path
import subprocess
import sys
import time
import types
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_release_suite  # noqa: E402


def silent_process(test):
    """A process that stays running and prints nothing."""
    read, write = os.pipe()
    test.addCleanup(os.close, write)
    stdout = os.fdopen(read, 'rb')
    return types.SimpleNamespace(stdout=stdout)


def printing(*lines):
    return types.SimpleNamespace(stdout=io.BytesIO(''.join(f'{line}\n' for line in lines).encode()))


class VerdictTest(unittest.TestCase):
    def setUp(self):
        for name, value in (('POLL', 0.01), ('SILENCE', 0.1)):
            patcher = mock.patch.object(run_release_suite, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        out = mock.patch('sys.stdout', io.StringIO())
        out.start()
        self.addCleanup(out.stop)

    def test_reads_either_verdict(self):
        for line in 'All tests passed!', 'Some tests failed.':
            self.assertEqual(run_release_suite.verdict(printing('00:01 +1: a', f'00:02 +1: {line}'), 60), line)

    def test_output_that_ends_without_a_verdict_is_none(self):
        self.assertIsNone(run_release_suite.verdict(printing('00:01 +1: a'), 60))

    def test_a_dead_app_ends_the_wait(self):
        started = time.monotonic()
        self.assertIsNone(run_release_suite.verdict(silent_process(self), 60, lambda: True))
        self.assertLess(time.monotonic() - started, 5)

    def test_silence_ends_the_wait_on_android(self):
        started = time.monotonic()
        self.assertIsNone(run_release_suite.verdict(silent_process(self), 60, lambda: False))
        self.assertLess(time.monotonic() - started, 5)

    def test_a_desktop_run_waits_out_its_timeout(self):
        started = time.monotonic()
        self.assertIsNone(run_release_suite.verdict(silent_process(self), 0.3))
        self.assertGreaterEqual(time.monotonic() - started, 0.3)


class DeathCheckTest(unittest.TestCase):
    def check(self, *replies):
        def run(*_, **__):
            reply = next(answers)
            if isinstance(reply, Exception):
                raise reply
            return types.SimpleNamespace(stdout=reply)
        answers = iter(replies)
        patcher = mock.patch.object(run_release_suite.subprocess, 'run', run)
        patcher.start()
        self.addCleanup(patcher.stop)
        return run_release_suite.death_check(['adb'])

    def test_needs_two_misses_in_a_row_after_the_app_was_seen(self):
        dead = self.check('123\n', '', '123\n', '', '')
        self.assertEqual([dead() for _ in range(5)], [False, False, False, False, True])

    def test_an_app_never_seen_is_not_called_dead(self):
        dead = self.check('', '', '', '')
        self.assertEqual([dead() for _ in range(4)], [False] * 4)

    def test_an_unresponsive_device_counts_as_a_miss(self):
        hung = subprocess.TimeoutExpired('adb', 30)
        dead = self.check('123\n', hung, hung)
        self.assertEqual([dead() for _ in range(3)], [False, False, True])


# From the build logs of jobs 115996940001 and 116031028600.
HTTP_500 = ('Verified download failed: https://github.com/a/b/releases/download/c/d.so: '
            'HttpException: HTTP 500, uri = https://github.com/a/b/releases/download/c/d.so')
ZIP = ('Warning: An error occurred while preparing SDK package NDK (Side by side) '
       '28.2.13676358: Error on ZipFile unknown archive.')
# The same client's words in job 116023056045's test phase.
LOOKUP = ("Verified download failed: https://storage.googleapis.com/a/b.so: ClientException "
          "with SocketException: Failed host lookup: 'storage.googleapis.com' (OS Error: "
          "No address associated with hostname, errno = 7), uri=https://storage.googleapis.com/")


class BuildTest(unittest.TestCase):
    def build(self, *runs):
        """build() over (status, lines) per run; returns the commands run, what
        was printed, and the failure's exit status, if any."""
        answers = iter(runs)
        commands = []

        def popen(command, **_):
            commands.append(command)
            status, lines = next(answers)
            return types.SimpleNamespace(stdout=printing(*lines).stdout, wait=lambda: status)
        args = types.SimpleNamespace(define=[], target='android', suite='a.dart',
                                     android_platform='android-x64')
        printed = io.StringIO()
        status = None
        with mock.patch.object(run_release_suite.subprocess, 'Popen', popen), \
                mock.patch.object(run_release_suite.time, 'sleep') as sleep, \
                mock.patch('sys.stdout', printed):
            try:
                run_release_suite.build(args)
            except subprocess.CalledProcessError as error:
                status = error.returncode
        self.assertEqual(sleep.call_count, max(len(commands) - 1, 0))
        return commands, printed.getvalue(), status

    def test_a_clean_build_runs_once(self):
        commands, printed, status = self.build((0, ['Built app-release.apk']))
        self.assertEqual((len(commands), status), (1, None))
        self.assertIn('Built app-release.apk', printed)
        self.assertNotIn('::warning::', printed)

    def test_a_network_error_builds_once_more_and_warns(self):
        for line in (HTTP_500, ZIP, LOOKUP,
                     'Verified download failed: https://a/b.so: SocketException: Connection reset',
                     'Verified download failed: https://a/b.so: TimeoutException after 0:01:00.000000'):
            commands, printed, status = self.build((1, [line, 'BUILD FAILED in 4m 3s']),
                                                   (0, ['Built']))
            self.assertEqual((len(commands), status), (2, None), line)
            self.assertEqual(commands[0], commands[1])
            self.assertIn('::warning::', printed)
            self.assertIn(line, printed)

    def test_a_second_network_error_is_red(self):
        commands, _, status = self.build((1, [HTTP_500]), (7, [HTTP_500]), (0, []))
        self.assertEqual((len(commands), status), (2, 7))

    def test_a_second_failure_of_another_kind_is_red(self):
        commands, _, status = self.build((1, [HTTP_500]), (1, ['Error: boom']), (0, []))
        self.assertEqual((len(commands), status), (2, 1))

    def test_any_other_build_error_is_red_at_once(self):
        for line in ("lib/main.dart:3:1: Error: Expected ';' after this.",
                     'Verified download failed: https://a/b.so: SHA-256 mismatch',
                     'Verified download failed: https://a/b.so: HttpException: HTTP 404, uri = https://a/b.so',
                     'Verified download failed: https://a/b.so: HttpException: HTTP 403, uri = https://a/b.so',
                     'Verified download failed: https://a/b.so: ClientException: Redirect limit exceeded',
                     "lib/main.dart:3:1: Error: Undefined name 'SocketException'.",
                     'lib/main.dart:4:1: Error: HTTP 500 is not a type.',
                     'Verified download failed: https://a/b.so: HandshakeException: certificate',
                     'FAILURE: Build failed with an exception.'):
            commands, printed, status = self.build((1, [line]), (0, []))
            self.assertEqual((len(commands), status), (1, 1), line)
            self.assertNotIn('::warning::', printed)

    def test_network_words_in_a_build_that_passed_do_not_rebuild(self):
        commands, printed, status = self.build((0, [HTTP_500]))
        self.assertEqual((len(commands), status), (1, None))
        self.assertNotIn('::warning::', printed)


class ExitCodeTest(unittest.TestCase):
    def run_main(self, process, dead=None, target=('--target', 'linux')):
        args = ['run_release_suite.py', *target, '--suite', 'a.dart', '--timeout', '1']
        with mock.patch.object(sys, 'argv', args), \
                mock.patch.object(run_release_suite, 'build'), \
                mock.patch.object(run_release_suite, 'launch', return_value=(process, lambda: None, dead)), \
                mock.patch('sys.stdout', io.TextIOWrapper(io.BytesIO())), \
                self.assertRaises(SystemExit) as caught:
            run_release_suite.main()
        return caught.exception.code

    def test_only_a_passing_report_exits_zero(self):
        self.assertEqual(self.run_main(printing('All tests passed!')), 0)
        self.assertEqual(self.run_main(printing('Some tests failed.')), 1)

    def test_no_report_exits_nonzero(self):
        self.assertEqual(self.run_main(printing('00:01 +1: a')), 1)

    def test_a_hung_device_still_exits_nonzero(self):
        android = ('--target', 'android', '--device', 'emulator-5554')
        hung = subprocess.TimeoutExpired('adb', 60)
        with mock.patch.object(run_release_suite.subprocess, 'run', side_effect=hung) as run:
            self.assertEqual(self.run_main(printing('00:01 +1: a'), target=android), 1)
        self.assertIn('logcat', run.call_args.args[0])


if __name__ == '__main__':
    unittest.main()
