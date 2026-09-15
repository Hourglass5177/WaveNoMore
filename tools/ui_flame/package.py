"""整理 Compatibility 采样：12 秒 60 fps 视频、动图、近景及运动检查。"""
import argparse,json,os,shutil,subprocess,sys
from pathlib import Path
import cv2
import numpy as np
from PIL import Image,ImageDraw,ImageFont
GAME=Path(__file__).resolve().parents[2];RAW=GAME/'build/ui-flame';OUT=GAME/'outputs/ui-flame'
sys.path.insert(0,str(RAW/'python-deps'))

def ffmpeg():
    configured=os.environ.get('FFMPEG') or shutil.which('ffmpeg')
    if configured:return configured
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()

def encode(mode):
    folder=RAW/f'{mode}-1920';assert len(list(folder.glob('*.png')))==720,(mode,'采样尚未完成')
    name=['red-blue','horizontal','old-new'][mode]
    cmd=[ffmpeg(),'-hide_banner','-loglevel','error','-y','-threads','2','-framerate','60','-i',str(folder/'%04d.png'),'-frames:v','720','-vf','scale=1280:720:flags=lanczos','-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(OUT/(name+'.mp4'))]
    subprocess.run(cmd,check=True)
    for color,x in [('red',310),('blue',1030)] if mode==0 else []:
        filters=f'fps=20,crop=580:870:{x}:100,scale=348:522:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=sierra2_4a'
        subprocess.run([ffmpeg(),'-hide_banner','-loglevel','error','-y','-threads','2','-framerate','60','-i',str(folder/'%04d.png'),'-filter_complex',filters,'-loop','0',str(OUT/(color+'.gif'))],check=True)
    if mode==0:
        subprocess.run([ffmpeg(),'-hide_banner','-loglevel','error','-y','-threads','2','-framerate','60','-i',str(folder/'%04d.png'),'-vf','crop=540:350:330:100,scale=1080:700:flags=lanczos','-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(OUT/'closeup.mp4')],check=True)
    print('PACKAGED',name,flush=True)

def details():
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
    sheet=Image.new('RGB',(1800,690),(25,27,41));draw=ImageDraw.Draw(sheet)
    for i,frame in enumerate([0,9,18,27,36,45]):
        im=Image.open(RAW/'0-1920'/f'{frame:04d}.png').convert('RGB')
        # 三处固定观察窗：顶边、侧边、底边，同一段0.75秒的生长与消退。
        for row,box in enumerate([(450,100,750,300),(310,450,610,650),(440,750,740,950)]):
            part=im.crop(box).resize((300,200));sheet.paste(part,(i*300,row*230+30))
            draw.text((i*300+9,row*230+5),f'{frame/60:.2f} s',font=font,fill='white')
    sheet.save(OUT/'motion-poses.png')
    Image.open(RAW/'0-1920/0032.png').save(OUT/'red-blue.png')
    for mode,name in [(1,'horizontal'),(2,'old-new')]:Image.open(RAW/f'{mode}-1920/0032.png').save(OUT/(name+'.png'))
    (OUT/'resolutions').mkdir(exist_ok=True)
    for mode in [0,1]:
        for width in [1280,3840]:shutil.copy2(RAW/f'{mode}-{width}/0006.png',OUT/f'resolutions/{mode}-{width}.png')
    shutil.copy2(RAW/'performance.json',OUT/'performance.json')
    cards=''.join(f'<article><h2>{label}</h2><video controls loop muted preload="metadata" src="{name}.mp4"></video></article>' for name,label in [('red-blue','红蓝火框'),('horizontal','横向弹窗'),('old-new','原八帧与新燃烧'),('closeup','火舌近景')])
    (OUT/'index.html').write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>UI 火框</title><style>body{background:#191b29;color:#eee;font:16px system-ui;margin:32px}main{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}video{width:100%}h2{font-size:18px;font-weight:500}</style><h1>UI 火框</h1><main>'+cards+'</main></html>',encoding='utf-8')

def verify():
    result={}
    for name in ['red-blue','horizontal','old-new','closeup']:
        cap=cv2.VideoCapture(str(OUT/(name+'.mp4')));fps=cap.get(cv2.CAP_PROP_FPS);frames=0
        while True:
            ok,_=cap.read()
            if not ok:break
            frames+=1
        cap.release();assert fps==60. and frames==720,(name,fps,frames);result[name]={'fps':fps,'frames':frames}
    for color in ['red','blue']:
        im=Image.open(OUT/(color+'.gif'));duration=0
        for i in range(im.n_frames):im.seek(i);duration+=im.info.get('duration',0)
        assert duration==12000,(color,duration)
    # 从真实像素检查上升方向；只在火框左上缘的亮火焰中统计光流。
    means=[]
    for frame in range(10,660,10):
        a=np.array(Image.open(RAW/'0-1920'/f'{frame:04d}.png').convert('RGB'))[150:235,420:780]
        b=np.array(Image.open(RAW/'0-1920'/f'{frame+2:04d}.png').convert('RGB'))[150:235,420:780]
        ga=cv2.cvtColor(a,cv2.COLOR_RGB2GRAY);gb=cv2.cvtColor(b,cv2.COLOR_RGB2GRAY)
        flow=cv2.calcOpticalFlowFarneback(ga,gb,None,.5,3,19,4,5,1.2,0)
        mask=(ga>90)&(gb>90)
        if mask.sum()>20:means.append(float(np.median(flow[:,:,1][mask])))
    result['median_vertical_flow_px_per_2frames']=float(np.median(means))
    assert np.median(means)<0.,'未检测到火焰上升'
    (OUT/'verification.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print('4 videos: 720 frames / 60 fps; GIF: 12 s; flow:',np.median(means))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--mode',type=int);parser.add_argument('--verify',action='store_true');parser.add_argument('--details',action='store_true');args=parser.parse_args();OUT.mkdir(parents=True,exist_ok=True)
    if args.verify:verify()
    elif args.details:details()
    else:
        for mode in ([args.mode] if args.mode is not None else [0,1,2]):encode(mode)
