"""将 Godot 的原始提示录帧编码成两个完整循环，便于直接查看动态。"""
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[2] / "builds/controller-review"
frames = [Image.open(path).convert("RGB") for path in sorted((root / "gesture-frames").glob("*.png"))[:72]]
# GIF 使用 10 ms 时间单位；30/30/40 ms 交替保持原始 30 FPS 的总时长。
frames[0].save(root / "stick-motion.gif", save_all=True, append_images=frames[1:],
               duration=[30, 30, 40] * 24, loop=0, optimize=False, disposal=2)
print("stick-motion.gif: 72 frames, 2.4 seconds")
