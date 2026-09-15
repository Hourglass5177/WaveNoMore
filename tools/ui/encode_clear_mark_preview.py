"""将正式选关采样的字样区域放大两倍，编码完整呼吸周期；需要 Pillow。"""
from pathlib import Path
from PIL import Image
root = Path(__file__).resolve().parents[2] / "builds/clear-mark"
frames = []
for index in range(48):
    panels = []
    for kind in ("fc", "ap"):
        with Image.open(root / kind / f"{index:03}.png") as image:
            w, h = image.size
            crop = image.crop((int(w*.44), int(h*.31), int(w*.56), int(h*.40)))
            panels.append(crop.resize((480,200),Image.Resampling.LANCZOS).convert("RGB"))
    frame = Image.new("RGB",(960,200))
    frame.paste(panels[0],(0,0)); frame.paste(panels[1],(480,0))
    frames.append(frame)
# 共用调色板，避免每帧重映射产生额外颜色跳动。
strip = Image.new("RGB",(960,400))
strip.paste(frames[0],(0,0)); strip.paste(frames[24],(0,200))
palette = strip.quantize(colors=256)
frames = [frame.quantize(palette=palette,dither=Image.Dither.NONE) for frame in frames]
frames[0].save(root / "breathing.gif",save_all=True,append_images=frames[1:],duration=100,loop=0,optimize=False)
print(root / "breathing.gif")
