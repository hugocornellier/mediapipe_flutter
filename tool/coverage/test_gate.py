"""Unit tests for the coverage gate: python3 -B -m unittest tool/coverage/test_gate.py"""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gate  # noqa: E402

HERE = Path(__file__).resolve().parent


class GateTest(unittest.TestCase):
    matrix = {'face_landmarker': {
        'web': {'cpu': 'required', 'gpu': 'pending: step 2'},
        'windows': {'cpu': 'required', 'gpu': 'unsupported: no GPU runtime'}}}

    def row(self, platform, delegate, passed=True, suite='s'):
        return dict(task='face_landmarker', platform=platform, delegate=delegate,
                    passed=passed, suite=suite)

    def test_required_cells_need_a_passing_row(self):
        states, failures, _ = gate.evaluate(self.matrix, [self.row('web', 'cpu')])
        self.assertEqual(states[('face_landmarker', 'web', 'cpu')], 'pass')
        self.assertEqual(failures, ['face_landmarker / windows / cpu: no row recorded'])

    def test_a_failing_row_names_its_suite(self):
        rows = [self.row('web', 'cpu'), self.row('windows', 'cpu', passed=False, suite='desktop')]
        _, failures, _ = gate.evaluate(self.matrix, rows)
        self.assertEqual(failures, ['face_landmarker / windows / cpu: failed in desktop'])

    def test_any_pass_satisfies_a_cell(self):
        rows = [self.row('web', 'cpu', passed=False), self.row('web', 'cpu'),
                self.row('windows', 'cpu')]
        _, failures, _ = gate.evaluate(self.matrix, rows)
        self.assertEqual(failures, [])

    def test_passing_pending_cells_are_reported_ahead(self):
        rows = [self.row('web', 'cpu'), self.row('windows', 'cpu'), self.row('web', 'gpu')]
        states, failures, ahead = gate.evaluate(self.matrix, rows)
        self.assertEqual(failures, [])
        self.assertEqual(states[('face_landmarker', 'web', 'gpu')], 'ahead')
        self.assertEqual(len(ahead), 1)

    def test_matrix_covers_every_task_platform_and_delegate(self):
        matrix = gate.load_matrix()
        self.assertEqual(len(matrix), 15)
        for task, platforms in matrix.items():
            self.assertEqual(sorted(platforms), sorted(gate.PLATFORMS), task)
            for platform, delegates in platforms.items():
                self.assertEqual(sorted(delegates), ['cpu', 'gpu'], (task, platform))
                for status in delegates.values():
                    self.assertTrue(status == 'required' or status.startswith(
                        ('pending: ', 'unsupported: ')), status)

    def test_record_refuses_unsupported_cells(self):
        with tempfile.TemporaryDirectory() as directory:
            command = [sys.executable, '-B', str(HERE / 'record.py'), '--suite', 'x',
                       '--platform', 'windows', '--delegate', 'gpu', '--tasks', 'face_landmarker',
                       '--outcome', 'success', '--output-dir', directory]
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            command[command.index('gpu')] = 'cpu'
            subprocess.run(command, check=True, capture_output=True)
            rows = json.loads((Path(directory) / 'x.json').read_text())
            self.assertEqual(rows[0]['passed'], True)


if __name__ == '__main__':
    unittest.main()
