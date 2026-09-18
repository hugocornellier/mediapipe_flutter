import copy
import unittest

from compare_ios_face_benchmarks import compare


SCHEDULE = [0, 0, 0, 1, 1, 0, 0, 2, 2, 0, 0, 3, 3, 0]


def campaign():
    metadata = {'schema': 1, 'frames': 3, 'rounds': 1, 'warmup': 1, 'sdk': '1.0.1',
                'workload': 'fixture', 'model_sha256': 'model', 'photo_sha256': 'photo',
                'fixtures': [{'sha256': 'pixels'}]}
    device = {'machine': 'iPhone16,1', 'ios': '26.5', 'thermal_state': 0, 'low_power_mode': False}
    return [{**copy.deepcopy(metadata), 'variant': variant, 'event': 'complete',
             'device_start': device.copy(), 'device_end': device.copy(),
             'runs': [{'case': '480x640/cpu/33ms/public_api', 'round': 0,
                       'samples_us': [{'total': {0: 10000, 1: 8000, 2: 9900, 3: 12000}[variant]}
                                      for _ in range(3)],
                       'landmarks': [0.5] * (478 * 3)}]}
            for variant in SCHEDULE]


class ComparisonTest(unittest.TestCase):
    def test_distinguishes_improvement_noise_and_regression(self):
        rows = compare(campaign(), SCHEDULE)['comparison']
        self.assertEqual([r['verdict'] for r in rows], ['improved', 'inconclusive', 'regressed'])
        self.assertAlmostEqual(rows[0]['reduction_percent'], 20)

    def test_measured_noise_can_prevent_acceptance(self):
        data = campaign()
        data[1]['runs'][0]['samples_us'] = [{'total': 15000}] * 3
        row = compare(data, SCHEDULE)['comparison'][0]
        self.assertEqual(row['verdict'], 'inconclusive')
        self.assertGreater(row['acceptance_floor_percent'], 20)

    def test_both_candidate_launches_must_improve(self):
        data = campaign()
        data[4]['runs'][0]['samples_us'] = [{'total': 11000}] * 3
        self.assertEqual(compare(data, SCHEDULE)['comparison'][0]['verdict'], 'inconclusive')

    def test_rejects_changed_pixels_outputs_and_thermal_state(self):
        for mutate in (
            lambda data: data[3]['fixtures'][0].update(sha256='changed'),
            lambda data: data[3]['runs'][0]['landmarks'].__setitem__(0, .51),
            lambda data: data[3]['device_end'].update(thermal_state=1),
            lambda data: data[3]['runs'][0]['samples_us'].pop(),
        ):
            with self.subTest(mutate=mutate):
                data = campaign()
                mutate(data)
                with self.assertRaises(ValueError):
                    compare(data, SCHEDULE)


if __name__ == '__main__':
    unittest.main()
