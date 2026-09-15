"""核对当前连续卷流的原生透明画面；曲线、网格及路程由 Godot 专项测试验证。"""
from pathlib import Path
import json
import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
captures = sorted((ROOT / 'build/boundary-animation/vortex-alpha').glob('*.png'))
assert len(captures) == 16, '先运行 Compatibility 波浪专项，生成 16 个透明采样'
closest = 1000.0
for path in captures:
    alpha = np.array(Image.open(path))[:, :, 3]
    _, labels = cv2.connectedComponents((alpha > 32).astype('uint8'))
    left, right = labels[540, 740], labels[540, 1180]
    assert left > 0 and right > 0 and left != right, path.name + ' 两股水体开口被连接'
    y, x = np.nonzero(alpha[440:641, 860:1061] > 2)
    radius = np.hypot(x - 100, y - 100)
    if len(radius):
        closest = min(closest, float(radius.min()))
    assert not len(radius) or radius.min() >= 76, path.name + ' 侵入中央观察空间'
report = {'native_phases': len(captures), 'nearest_water_px': closest,
          'opposite_gaps_open': True}
(ROOT / 'build/boundary-animation/vortex-stream-coverage.json').write_text(
    json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report))

