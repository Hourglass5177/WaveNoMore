"""原生 60 fps 全景、近景和同刻对照；不在编码阶段补帧。"""
from pathlib import Path
import os,cv2,argparse
import numpy as np
from PIL import Image,ImageDraw,ImageFont
OUT=Path(__file__).resolve().parents[2]/'build/boundary-animation'
parser=argparse.ArgumentParser();parser.add_argument('--source',default='vortex-round-final');parser.add_argument('--before',default='vortex-before');parser.add_argument('--name',default='vortex');args=parser.parse_args()
os.chdir(OUT)
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
frames=sorted(Path(args.source).glob('[0-9]*.png'))
assert len(frames)>0
outputs=[(args.name+'-full-60fps.webm',(1920,1080)),(args.name+'-close-60fps.webm',(960,720)),(args.name+'-comparison-60fps.webm',(1440,900))]
writers=[cv2.VideoWriter(name,cv2.VideoWriter_fourcc(*'VP80'),60,size) for name,size in outputs]
assert all(w.isOpened() for w in writers)
comparison_count=0
for path in frames:
    source=Image.open(path).convert('RGB')
    writers[0].write(cv2.cvtColor(np.array(source),cv2.COLOR_RGB2BGR))
    close=source.crop((600,270,1320,810)).resize((960,720),Image.Resampling.LANCZOS)
    writers[1].write(cv2.cvtColor(np.array(close),cv2.COLOR_RGB2BGR))
    # 对照只使用双方共同的真实采样时间，不循环旧片来凑足长度。
    if not (Path(args.before)/path.name).exists():continue
    comparison_count+=1
    pair=Image.new('RGB',(1440,900),(48,45,61));draw=ImageDraw.Draw(pair)
    for n,folder in enumerate([args.before,args.source]):
        image=Image.open(Path(folder)/path.name).convert('RGB')
        pair.paste(image.crop((0,270,1920,810)).resize((1440,405),Image.Resampling.LANCZOS),(0,n*450+40))
        draw.text((16,n*450+8),['修改前','当前卷流'][n],font=font,fill='white')
    writers[2].write(cv2.cvtColor(np.array(pair),cv2.COLOR_RGB2BGR))
for writer in writers:writer.release()
for index,(name,size) in enumerate(outputs):
    video=cv2.VideoCapture(name)
    assert video.get(cv2.CAP_PROP_FPS)==60 and video.get(cv2.CAP_PROP_FRAME_COUNT)==(comparison_count if index==2 else len(frames)) and video.read()[0]
    video.release()
sheet=Image.new('RGB',(1440,960),(48,45,61));draw=ImageDraw.Draw(sheet)
for n,i in enumerate(np.linspace(0,len(frames)-1,8,dtype=int)):
    image=Image.open(frames[i]).convert('RGB').crop((620,270,1300,810)).resize((360,286),Image.Resampling.LANCZOS)
    x=n%4*360;y=n//4*320;sheet.paste(image,(x,y+30));draw.text((x+10,y+5),f'{i/60:.2f} s',font=font,fill='white')
sheet=sheet.crop((0,0,1440,640));sheet.save(args.name+'-phases.png')
print(f'VORTEX PACKAGED: {len(frames)/60:g} seconds, {len(frames)} native frames, 60 fps; full / close / comparison')
