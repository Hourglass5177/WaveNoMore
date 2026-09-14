"""将 Compatibility 实拍整理为三只随从的双侧对照，不改动画素材。"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parents[2] / "build" / "pet-runtime"
PETS = [("nu_tu_fu", "蝠漆漆"), ("yi_huo_she", "苹果蛇"), ("gui_jin_yang", "羊头仔")]
FONT = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 22)
# 上下保持实际游戏的旋转关系，按原始像素裁取主角与随从区域。
REGIONS = [(40, 160, 480, 560), (1440, 520, 1880, 920)]


def contact(frame: int) -> Image.Image:
    result = Image.new("RGB", (1320, 844), "#17151d")
    draw = ImageDraw.Draw(result)
    for column, (pet, name) in enumerate(PETS):
        with Image.open(OUT / pet / f"{frame:04d}.png") as shot:
            for row, region in enumerate(REGIONS):
                result.paste(shot.crop(region).convert("RGB"), (440 * column, 44 + 400 * row))
        draw.text((440 * column + 220, 20), name, font=FONT, anchor="mm", fill="#e4dcc6")
    return result


if __name__ == "__main__":
    frames = [contact(index) for index in range(174)]
    frames[10].save(OUT / "both-worlds.png")
    # 审看动图按 20 fps 缩图，原始 30 fps 实拍 PNG 保留在各随从目录。
    preview = [frames[index].resize((990, 633), Image.Resampling.LANCZOS)
               for index in [int(i * 1.5) for i in range(116)]]
    durations = [50] * len(preview)
    durations[-1] = 600
    palette = preview[27].quantize(colors=128)
    preview = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in preview]
    preview[0].save(OUT / "companions-in-game.gif", save_all=True,
                    append_images=preview[1:], duration=durations, loop=0, disposal=1, optimize=False)
    keyposes = Image.new("RGB", (1320, 844 * 3), "#17151d")
    for row, index in enumerate([41, 126, 144]):
        keyposes.paste(contact(index), (0, row * 844))
    keyposes.save(OUT / "runtime-keyposes.png")
    print("已整理双侧实拍动图、常态对照与技能/死亡关键帧。")
