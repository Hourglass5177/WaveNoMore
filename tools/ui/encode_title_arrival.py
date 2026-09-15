"""从正式入口的 60 FPS 录制截取控制器说明至标题提示的过渡，保留原速度。"""
from pathlib import Path
import cv2
from PIL import Image

root = Path(__file__).resolve().parents[2] / "builds/title-review"
video = cv2.VideoCapture(str(root / "title-transition.avi"))
frames = []
# 7.4 秒确认说明，8 秒开始溶解，约 9.8 秒完成提示淡入。
for index in range(426, 619, 3):
    video.set(cv2.CAP_PROP_POS_FRAMES, index)
    ok, frame = video.read()
    if not ok:
        raise RuntimeError(f"录制缺少第 {index} 帧")
    frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    frames.append(Image.fromarray(frame).resize((960, 540), Image.Resampling.LANCZOS))
video.release()
# 全过程共享调色板，避免每帧量化让暗部和颗粒额外闪动。
sample = Image.new("RGB", (960, 540 * 6))
for i, index in enumerate([0, 18, 27, 34, 43, 60]):
    sample.paste(frames[index], (0, 540 * i))
palette = sample.quantize(colors=256)
frames = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
frames[0].save(root / "title-arrival.gif", save_all=True, append_images=frames[1:], duration=50, loop=0, optimize=False)
print(root / "title-arrival.gif")
