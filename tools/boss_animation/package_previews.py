"""整理原生渲染采样。视频 60 fps，GIF 30 fps；PNG 源帧保留。"""
from pathlib import Path
import argparse,json
import numpy as np
from PIL import Image,ImageDraw,ImageFont
import cv2
GAME=Path(__file__).resolve().parents[2]
SOURCE=GAME/'build/boss-animation'
OUT=GAME/'outputs/boss-animation'
IDS=['bat','snake','goat','goat_eye']
FONT=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
NAMES={'bat':'蝙蝠','snake':'蛇','goat':'羊头','goat_eye':'羊头·眼球形态'}
def source_dir(key,clip):
    return SOURCE/key/('phase_break' if key=='goat' and clip=='death' else clip)
def composite(path,size=None):
    a=np.array(Image.open(path).convert('RGBA'),dtype=np.float32)
    # SubViewport 透明采样为预乘色，合成一次，避免边缘和主体被重复乘透明度。
    rgb=np.clip(a[:,:,:3]+np.array([41,37,48])*(1-a[:,:,3:4]/255),0,255).astype(np.uint8)
    im=Image.fromarray(rgb)
    return im.resize(size,Image.Resampling.LANCZOS) if size else im
def bake(selected=None):
    for key in IDS:
        if selected and selected!=key:continue
        p=GAME/'assets/bosses/animation_studies'/key/'death_pose.png'
        a=np.array(Image.open(p).convert('RGBA'),dtype=np.float32)
        a[:,:,:3]=np.minimum(255,a[:,:,:3]*255/np.maximum(a[:,:,3:4],1))
        Image.fromarray(a.astype(np.uint8)).save(p)
def audit():
    OUT.mkdir(parents=True,exist_ok=True)
    canvas=Image.new('RGB',(1440,1000),(41,37,48));draw=ImageDraw.Draw(canvas)
    for row,key in enumerate(['snake','goat','goat_eye']):
        paths=sorted((SOURCE/key/'alignment').glob('*-full.png'))
        for col,path in enumerate(paths):
            frame=path.name.split('-')[0];points=json.loads(path.with_name(frame+'.json').read_text())
            full=np.array(Image.open(path));body=np.array(Image.open(path.with_name(frame+'-body.png')))
            if key.startswith('goat'):
                yy,xx=np.indices(full.shape[:2]);allowed=np.zeros(full.shape[:2],bool)
                for x,y in points:allowed|=((xx-x)/75)**2+((yy-y)/65)**2<1
                error=np.max(np.abs(full.astype(int)-body.astype(int)),axis=2)
                assert error[~allowed].max()==0,(key,frame,'眼区外发生光照变化',error[~allowed].max())
            box=(350,300,1150,940) if key!='snake' else (180,140,1380,970)
            im=composite(path).crop(box);im.thumbnail((350,290),Image.Resampling.LANCZOS)
            canvas.paste(im,(col*360+(350-im.width)//2,row*330+35))
            draw.text((col*360+10,row*330+5),f'{NAMES[key]} · {int(frame)/60:.2f} s',font=FONT,fill='white')
    canvas.save(OUT/'alignment-review.png');print('眼区外像素差为 0：两种羊头 × 4 个姿势')
def package(selected=None,selected_clip=None):
    OUT.mkdir(parents=True,exist_ok=True)
    for key in IDS:
        if selected and key!=selected:continue
        for clip in ['attack','hurt','death','combo']+(['phase_break','two_phase'] if key=='goat' else []):
            if selected_clip and clip!=selected_clip:continue
            paths=sorted(source_dir(key,clip).glob('*.png'));expected=[f'{i:04d}.png' for i in range(len(paths))]
            assert [p.name for p in paths]==expected,(key,clip,'缺帧')
            target=OUT/f'{key}-{clip}.webm'
            # OpenCV 写入相对 ASCII 路径，避开 Windows 视频后端的宽字符路径限制。
            video=cv2.VideoWriter(str(target.relative_to(GAME)),cv2.VideoWriter_fourcc(*'VP80'),60,(768,640))
            assert video.isOpened()
            frames=[]
            for i,p in enumerate(paths):
                im=composite(p,(768,640));video.write(cv2.cvtColor(np.array(im),cv2.COLOR_RGB2BGR))
                if i%2==0:frames.append(im)
            video.release()
            frames[0].save(OUT/f'{key}-{clip}.gif',save_all=True,append_images=frames[1:],duration=[30,30,40]*(len(frames)//3)+[30,30][:len(frames)%3],loop=0,optimize=False)
            print(key,clip,len(paths),'frames',flush=True)
    stills()
    index()
def stills():
    OUT.mkdir(parents=True,exist_ok=True)
    sheet=Image.new('RGB',(1536,1280),(41,37,48));draw=ImageDraw.Draw(sheet)
    for row,key in enumerate(IDS):
        for col,clip in enumerate(['attack','hurt','death']):
            paths=sorted(source_dir(key,clip).glob('*.png'));idx=90 if clip=='attack' else (47 if clip=='hurt' else int((.4+({'bat':1.6,'snake':1.85,'goat':2.,'goat_eye':4.1}[key]))*60))
            im=composite(paths[idx],(512,426));sheet.paste(im.crop((0,50,512,340)),(col*512,row*320+30))
            draw.text((col*512+15,row*320+5),NAMES[key]+' · '+('真眼觉醒' if key=='goat' and clip=='death' else {'attack':'攻击','hurt':'受击','death':'死亡'}[clip]),font=FONT,fill='white')
    sheet.save(OUT/'all-states.png')
    sheet=Image.new('RGB',(1920,1280),(41,37,48));draw=ImageDraw.Draw(sheet)
    for row,key in enumerate(IDS):
        for col,t in enumerate([.5,1.5,2.4,4.,4.85] if key=='goat_eye' else [.5,1.1,1.5,2.,2.8]):
            im=composite(source_dir(key,'death')/f'{round((t+.4)*60):04d}.png',(384,320));sheet.paste(im,(col*384,row*320))
            draw.text((col*384+8,row*320+6),NAMES[key]+f' · {t:.1f} s',font=FONT,fill='white')
    sheet.save(OUT/'death-poses.png')
def index():
    cards=[]
    for key in IDS:
        for clip,label in [('attack','攻击'),('hurt','受击'),('death','死亡'),('combo','攻击中受击')]:
            frame=90 if clip in ['attack','combo'] else (47 if clip=='hurt' else round((.4+{'bat':1.6,'snake':1.85,'goat':2.,'goat_eye':4.1}[key])*60))
            composite(source_dir(key,clip)/f'{frame:04d}.png',(768,640)).save(OUT/f'{key}-{clip}-poster.png')
            if key=='goat' and clip=='death':label='真眼觉醒'
            cards.append(f'<article><h2>{NAMES[key]} · {label}</h2><video controls loop muted preload="metadata" poster="{key}-{clip}-poster.png" src="{key}-{clip}.webm"></video></article>')
    if (OUT/'goat-two_phase.webm').exists():cards.insert(0,'<article style="grid-column:span 2"><h2>羊头 · 两阶段完整演示</h2><video controls loop muted preload="metadata" src="goat-two_phase.webm"></video></article>')
    (OUT/'index.html').write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>BOSS 动画</title><style>body{margin:30px;background:#292530;color:#eee;font:16px sans-serif}h1{font-size:26px}h2{font-size:16px;font-weight:500}main{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:24px}video{width:100%;background:#292530;border-radius:8px}@media(max-width:950px){main{grid-template-columns:repeat(2,minmax(0,1fr))}}</style><h1>BOSS 动画</h1><p>60 fps · 拖动时间条查看姿势</p><main>'+''.join(cards)+'</main></html>',encoding='utf-8')
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--prepare-bakes',action='store_true');parser.add_argument('--audit',action='store_true');parser.add_argument('--index',action='store_true');parser.add_argument('--stills',action='store_true');parser.add_argument('--id',choices=IDS);parser.add_argument('--clip',choices=['attack','hurt','death','combo','phase_break','two_phase']);args=parser.parse_args()
    if args.prepare_bakes:bake(args.id)
    elif args.audit:audit()
    elif args.index:index()
    elif args.stills:stills()
    else:package(args.id,args.clip)
