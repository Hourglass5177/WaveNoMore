"""输出羊头觉醒、裂光终结、连续演示与额眼近景，视频 60 fps。"""
import shutil,sys
import cv2
import numpy as np
from PIL import Image,ImageDraw
from package_previews import package,composite,FONT,OUT,SOURCE,GAME,index

def details(closeup=True):
    for clip,key,times in [('phase_break','goat',[.2,.8,1.3,1.7,2.2,3.1]),('death','goat_eye',[.3,1.5,2.5,3.8,4.8,5.3,6.2,6.9])]:
        sheet=Image.new('RGB',(400*len(times),440),(41,37,48));draw=ImageDraw.Draw(sheet)
        for i,t in enumerate(times):
            im=composite(SOURCE/key/clip/f'{round((t+.4)*60):04d}.png').crop((400,180,1136,1000)).resize((400,440))
            sheet.paste(im,(i*400,0));draw.text((i*400+10,10),f'{t:.2f} s',font=FONT,fill='white')
        sheet.save(OUT/f'goat-{clip}-poses.png')
    if not closeup:return
    paths=sorted((SOURCE/'goat/phase_break').glob('*.png'))
    video=cv2.VideoWriter(str((OUT/'goat-eye-closeup.webm').relative_to(GAME)),cv2.VideoWriter_fourcc(*'VP80'),60,(640,480))
    assert video.isOpened();frames=[]
    for i,path in enumerate(paths):
        im=composite(path).crop((615,440,935,680)).resize((640,480),Image.Resampling.LANCZOS)
        video.write(cv2.cvtColor(np.array(im),cv2.COLOR_RGB2BGR))
        if i%2==0:frames.append(im)
        if i==144:im.save(OUT/'goat-eye-closeup.png')
    video.release()
    frames[0].save(OUT/'goat-eye-closeup.gif',save_all=True,append_images=frames[1:],duration=([30,30,40]*len(frames))[:len(frames)],loop=0,optimize=False)

if __name__=='__main__':
    package('goat','phase_break')
    # 旧链接继续指向一阶段结束的新演示，避免总览播放过时的碎裂死亡。
    for ext in ['webm','gif']:shutil.copy2(OUT/f'goat-phase_break.{ext}',OUT/f'goat-death.{ext}')
    if '--reveal-only' not in sys.argv:package('goat_eye','death')
    package('goat','two_phase')
    details();index()
