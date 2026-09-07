"""合成数据只验证拟合，不代替音乐识别准确率验证。"""
import unittest
import json
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch
import numpy as np
from analyze import FIT_VERSION, fit_grid, main


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
            self.assertTrue(result['anchor_confirmed'])
            self.assertEqual(result['version'], FIT_VERSION)

    def test_half_time_and_phase_jump_do_not_tilt_tempo(self):
        # 前段只检出隔拍；中段整体相位跳 100 ms，不能拿相位差当变速斜率。
        early = 0.88 + np.arange(32) * 60 / 69
        later = early[-1] + 60 / 69 + 0.1 + np.arange(180) * 60 / 138
        result = fit_grid(np.r_[early, later], np.r_[early[::4], later[::4]])
        self.assertAlmostEqual(result['bpm'], 138, delta=0.001)
        self.assertEqual(result['anchor'], 0.88)
        self.assertTrue(any(not w['stable'] for w in result['windows']))
        self.assertTrue(any(w['beat_scale'] == 2 for w in result['windows']))

    def test_reference_uses_detected_downbeat_without_global_intercept(self):
        b = 1.23456789 + np.arange(160) * 0.5
        b[80:] += 0.08
        result = fit_grid(b, b[::4])
        self.assertEqual(result['anchor'], 1.23456789)
        self.assertAlmostEqual(result['bpm'], 120, delta=0.001)

    def test_selected_range_refits_without_earlier_section(self):
        a = np.arange(64) * 0.5
        b = 40 + np.arange(64) * 0.6
        result = fit_grid(np.r_[a, b], np.r_[a[::4], b[::4]], [40, 80])
        self.assertAlmostEqual(result['bpm'], 100, delta=0.001)
        self.assertEqual(result['anchor'], 40)
        self.assertEqual(result['meter'], 4)

    def test_no_reliable_downbeat_is_explicit(self):
        result = fit_grid(np.arange(32) * 0.5, [])
        self.assertFalse(result['anchor_confirmed'])
        self.assertEqual(result['meter'], 0)

    def test_different_tempi_remain_visible(self):
        a = np.arange(64) * 0.5
        b = 35 + np.arange(64) * 0.57
        result = fit_grid(np.r_[a, b], np.r_[a[::4], b[::4]])
        # 不能把互不一致的段落都报告为稳定。
        self.assertTrue(any(not w['stable'] for w in result['windows']))
        self.assertTrue(any(w['stable'] for w in result['windows']))
        self.assertLess(min(abs(result['bpm'] - 120), abs(result['bpm'] - 60 / 0.57)), 0.001)

    def test_competing_tempo_clusters_never_average_into_invented_tempo(self):
        for second_period in (0.56, 0.65, 0.73):
            a = 1 + np.arange(80) * 0.5
            b = 50 + np.arange(80) * second_period
            result = fit_grid(np.r_[a, b], np.r_[a[::4], b[::4]])
            # 半速／倍速选择可不同，但建议必须得到至少一组真实窗口支持。
            chosen_period = 60 / result['bpm']
            actual = [p * scale for p in (0.5, second_period) for scale in (0.5, 1, 2)]
            self.assertLess(min(abs(chosen_period - p) for p in actual), 0.00001)
            self.assertTrue(any(w['stable'] for w in result['windows']))

    def test_uncertain_meter(self):
        result = fit_grid(np.arange(20) * 0.5, [0, 2, 3.5, 5.5, 7])
        self.assertEqual(result['meter'], 0)

    def test_insufficient_beats(self):
        with self.assertRaises(ValueError):
            fit_grid([0, 0.5, 1], [])

    def test_refit_old_raw_cache_without_model_runtime(self):
        with tempfile.TemporaryDirectory() as folder:
            request, result = Path(folder) / 'request.json', Path(folder) / 'result.json'
            beats = (0.88 + np.arange(64) * 0.5).tolist()
            raw = {'version': 'beat-this-final0-v1', 'beats': beats, 'downbeats': beats[::4],
                   'fit': {'bpm': 120.5, 'anchor': 0.9198}, 'range': [0, 34]}
            request.write_text(json.dumps({'request_id': 7, 'raw': raw, 'fit_range': [0, 34]}))
            with patch.object(sys, 'argv', ['analyze', '--request', str(request), '--result', str(result)]), \
                    patch.dict(sys.modules, {'torch': None, 'beat_this': None}):
                self.assertEqual(main(), 0)
            value = json.loads(result.read_text(encoding='utf-8'))
            self.assertEqual(value['beats'], beats)
            self.assertEqual(value['fit_version'], FIT_VERSION)
            self.assertEqual(value['request_id'], 7)
            self.assertEqual(value['fit']['anchor'], 0.88)


if __name__ == '__main__':
    unittest.main()
