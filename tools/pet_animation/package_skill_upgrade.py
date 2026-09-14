"""整理实际渲染的新版技能与修改前后对照，保留逐帧 PNG。"""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont
from make_previews import gif

GAME = Path(__file__).resolve().parents[2]
OUT = GAME/'build/pet-skill-upgrade'
RENDER = GAME/'build/pet-animation'
FONT = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
PETS = [('bat','蝠漆漆'),('snake','苹果蛇'),('sheep','羊头仔')]


def tile(key, frame, before=False):
    folder = OUT/'before'/key/'trigger' if before else RENDER/key/'trigger'
    path = folder/f'{frame:04d}.png'
    # 旧动作结束后回到基准，不能反复循环旧短动画来冒充同一次技能。
    if not path.exists(): path = RENDER/key/'idle/0000.png'
    with Image.open(path) as source:
        rgba=source.convert('RGBA').resize((300,300),Image.Resampling.LANCZOS)
    canvas=Image.new('RGB',(300,330),'#302c39')
    canvas.paste(rgba,(0,30),rgba)
    return canvas


def main():
    new=[]; comparison=[]
    for frame in range(48):
        row=Image.new('RGB',(900,330),'#302c39')
        compare=Image.new('RGB',(600,990),'#302c39')
        for index,(key,name) in enumerate(PETS):
            cell=tile(key,frame)
            ImageDraw.Draw(cell).text((12,7),name,font=FONT,fill='#f3ede5')
            row.paste(cell,(index*300,0))
            for column,before in enumerate([True,False]):
                cell=tile(key,frame,before)
                ImageDraw.Draw(cell).text((12,7),name+' · '+('此前' if before else '新版'),font=FONT,fill='#f3ede5')
                compare.paste(cell,(column*300,index*330))
        new.append(row); comparison.append(compare)
    gif(new,OUT/'three-triggers.gif')
    gif(comparison,OUT/'before-after.gif')
    new[16].save(OUT/'three-triggers.png')
    comparison[16].save(OUT/'before-after.png')
    with Image.open(OUT/'skill-poses.png') as poses:
        poses.crop((0,600,1500,900)).save(OUT/'sheep-eyes-corrected.png')
    print(OUT/'three-triggers.gif')


if __name__=='__main__': main()
