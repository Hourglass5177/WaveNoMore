"""合成数据只验证拟合，不代替音乐识别准确率验证。"""
import unittest
import numpy as np
from analyze import fit_grid


class GridTests(unittest.TestCase):
    def test_meter_and_missing_beats(self):
        for meter in (3, 4):
            times = 1.25 + np.arange(160) * 60 / 137
            beats = times + np.sin(np.arange(160)) * 0.008
            beats = np.delete(beats, [11, 25, 33, 109])
            result = fit_grid(beats, times[::meter])
            self.assertAlmostEqual(result['bpm'], 137, delta=0.02)
            self.assertAlmostEqual(result['anchor'], 1.25, delta=0.01)
            self.assertEqual(result['meter'], meter)

    def test_uncertain_meter(self):
        result = fit_grid(np.arange(20) * 0.5, [0, 2, 3.5, 5.5, 7])
        self.assertEqual(result['meter'], 0)

    def test_insufficient_beats(self):
        with self.assertRaises(ValueError):
            fit_grid([0, 0.5, 1], [])


if __name__ == '__main__':
    unittest.main()
