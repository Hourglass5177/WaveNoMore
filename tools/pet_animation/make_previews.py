"""把真实渲染采样整理成动图与关键姿势图，不重绘原画。"""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

GAME=Path(__file__).resolve().parents[2]
ROOT=GAME/'build/pet-animation'
FONT=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',19)
SMALL=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',15)
BG='#a9a39e'


def on_canvas(frame,size=280):
    frame=frame.resize((size,size),Image.Resampling.LANCZOS)
    bg=Image.new('RGB',(size,size),BG)
    bg.paste(frame,(0,0),frame)
    return bg


def gif(frames,path,durations=None):
    sample=Image.new('RGB',(frames[0].width,frames[0].height*min(len(frames),12)))
    for n in range(min(len(frames),12)):
        sample.paste(frames[n*(len(frames)-1)//max(min(len(frames),12)-1,1)],(0,n*frames[0].height))
    palette=sample.quantize(colors=192)
    indexed=[frame.quantize(palette=palette,dither=Image.Dither.NONE) for frame in frames]
    # GIF 只支持百分之一秒；30/30/40 毫秒保留正确的平均 30 fps。
    timing=durations or [30 if i%3<2 else 40 for i in range(len(frames))]
    indexed[0].save(path,save_all=True,append_images=indexed[1:],duration=timing,loop=0,optimize=True,disposal=1)


def main():
    # 过渡演示来自实际 Spine 事件混合，不能用独立动画帧硬切冒充。
    demo=[Image.open(p).convert('RGB') for p in sorted((ROOT/'demo').glob('*.png'))]
    if len(demo)!=144:
        raise RuntimeError('请先运行 capture_review.gd 生成混合演示采样。')
    for key in ['bat','snake','sheep']:
        meta=json.loads((GAME/'assets/pets/animation_studies'/key/'animation.json').read_text(encoding='utf-8'))
        clips={clip:[Image.open(p).convert('RGBA') for p in sorted((ROOT/key/clip).glob('*.png'))] for clip in ['idle','trigger','death']}
        for clip,frames in clips.items():
            gif([on_canvas(f,360) for f in frames],ROOT/(key+'-'+clip+'.gif'))
        row=['bat','snake','sheep'].index(key)
        movie=[frame.crop((0,row*320,840,(row+1)*320)) for frame in demo]
        gif(movie,ROOT/(key+'-states.gif'))
        for clip,frames in clips.items():
            picks=[0,len(frames)//4,len(frames)//2,3*len(frames)//4,len(frames)-1]
            if clip=='death':picks=[0,12,27,42,54,62]
            sheet=Image.new('RGB',(len(picks)*240,280),BG);d=ImageDraw.Draw(sheet)
            for col,n in enumerate(picks):
                n=min(n,len(frames)-1)
                sheet.paste(on_canvas(frames[n],240),(col*240,32))
                d.text((col*240+10,8),f'{meta["name"]} {clip} {min(n/30,meta[clip]):.2f}s',font=SMALL,fill='#292531')
            sheet.save(ROOT/(key+'-'+clip+'-poses.png'))
    gif(demo,ROOT/'three-pets.gif')
    print(ROOT/'three-pets.gif')


if __name__=='__main__':main()
