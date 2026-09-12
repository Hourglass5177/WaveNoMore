"""生成柔光距离遮罩与 Tap 睫毛保护遮罩；美术替换后执行一次。

用法：python tools/generate_note_glow_masks.py [相对于工程的 PNG 路径 ...]
依赖 Pillow、NumPy。遮罩以 96 px 长边、2 倍采样、64 px 留边存储。
"""
from pathlib import Path
import sys
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
DEFAULTS = ["tap_base", "hold_note", "hold_head2"]

def distance_field(mask):
    """两遍八邻域距离变换；仅离线执行，足够平滑的轮廓不需要运行时模糊。"""
    height, width = mask.shape
    data = np.where(mask, 10000.0, 0.0).tolist()
    for ys, xs, direction in [(range(height), range(width), -1),
                               (range(height - 1, -1, -1), range(width - 1, -1, -1), 1)]:
        for y in ys:
            row = data[y]
            other_y = y + direction
            other = data[other_y] if 0 <= other_y < height else None
            for x in xs:
                near_x = x + direction
                if 0 <= near_x < width:
                    row[x] = min(row[x], row[near_x] + 1)
                if other is not None:
                    row[x] = min(row[x], other[x] + 1)
                    if x > 0: row[x] = min(row[x], other[x - 1] + 1.414214)
                    if x + 1 < width: row[x] = min(row[x], other[x + 1] + 1.414214)
    return np.asarray(data)

def generate(source):
    source = ROOT / source
    image = Image.open(source).convert("RGBA")
    ratio = 192 / max(image.size)
    size = tuple(max(1, round(v * ratio)) for v in image.size)
    alpha = np.asarray(image.resize(size, Image.Resampling.LANCZOS))[:, :, 3]
    inside = np.pad(alpha > 32, 128)
    distance = (distance_field(~inside) - distance_field(inside)) / 2
    # 16 位灰度避免大面积柔晕出现色阶；Godot 导入后保留线性数据。
    encoded = np.uint16(np.clip(distance / 128 + 0.5, 0, 1) * 65535)
    target = source.with_name(source.stem + "_glow.png")
    Image.fromarray(encoded).save(target)
    print(target.relative_to(ROOT))
    if source.stem == "tap_base":
        # 只保护眼眶外的中性浅色细节；眼眶内由原来的眼部遮罩处理。
        rgba = np.asarray(image, dtype=float) / 255
        eye = np.asarray(Image.open(source.with_name("tap_musk.png")).convert("L").resize(image.size), dtype=float) / 255
        rgb = rgba[:, :, :3]
        low, high = rgb.min(axis=2), rgb.max(axis=2)
        neutral = np.clip(1 - (high - low) / .16, 0, 1)
        bright = np.clip((low - .30) / .35, 0, 1)
        mask = neutral * bright * (1 - eye)
        # 闭合细小颗粒孔洞，睫毛的灰暗纹理也保留中性，轮廓不向外扩张。
        closed = Image.fromarray(np.uint8(np.round(mask * 255))).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
        mask = np.asarray(closed, dtype=float) * (1 - eye)
        target = source.with_name("tap_lashes.png")
        Image.fromarray(np.uint8(np.round(mask))).save(target)
        print(target.relative_to(ROOT))

if __name__ == "__main__":
    for path in sys.argv[1:] or [f"assets/image/note/{name}.png" for name in DEFAULTS]:
        generate(path)
