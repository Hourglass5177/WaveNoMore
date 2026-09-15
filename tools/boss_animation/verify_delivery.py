"""逐帧解码交付视频，核对帧率、时长、GIF 和原生画布边缘。"""
from pathlib import Path
import json,sys
import cv2
import numpy as np
from PIL import Image,ImageSequence
ROOT=Path(__file__).resolve().parents[2]
report=[]
for key in ['bat','snake','goat','goat_eye']:
    for clip in ['attack','hurt','death','combo']+(['phase_break','two_phase','eye-closeup'] if key=='goat' else []):
        if '--goat' in sys.argv and not (key=='goat' and clip in ['death','phase_break','two_phase','eye-closeup'] or key=='goat_eye' and clip=='death'):continue
        source_clip='phase_break' if key=='goat' and clip in ['death','eye-closeup'] else clip
        source=sorted((ROOT/'build/boss-animation'/key/source_clip).glob('*.png'))
        relative=Path('outputs/boss-animation')/f'{key}-{clip}.webm'
        video=cv2.VideoCapture(str(relative));assert video.isOpened(),str(relative)
        fps=video.get(cv2.CAP_PROP_FPS);assert abs(fps-60)<.001,(relative,fps)
        count=0
        while True:
            ok,frame=video.read()
            if not ok:break
            assert frame.shape[:2]==((480,640) if clip=='eye-closeup' else (640,768)),(relative,frame.shape)
            count+=1
        video.release();assert count==len(source),(relative,count,len(source))
        gif=Image.open(ROOT/relative.with_suffix('.gif'))
        milliseconds=sum(f.info.get('duration',0) for f in ImageSequence.Iterator(gif))
        assert abs(milliseconds/1000-count/60)<.05,(relative,'GIF duration',milliseconds)
        edge_peak=0
        for index in sorted({0,len(source)//4,len(source)//2,len(source)*3//4,len(source)-1}):
            alpha=np.array(Image.open(source[index]))[:,:,3]
            edge_peak=max(edge_peak,int(max(alpha[0].max(),alpha[-1].max(),alpha[:,0].max(),alpha[:,-1].max())))
        is_final=key=='goat_eye' and clip=='death' or clip=='two_phase'
        if not is_final:assert edge_peak==0,(relative,'原生画布裁切',edge_peak)
        if is_final:
            assert np.array(Image.open(source[-1]))[:,:,3].max()==0,(relative,'死亡残留')
            start=.4 if clip=='death' else 6.7
            for age in [5.15,5.40,5.633333]:
                white=np.array(Image.open(source[round((start+age)*60)]))
                assert white.min()>=254,(relative,'纯白保持不完整',age)
        elif clip=='death' and key!='goat':assert np.array(Image.open(source[-1]))[:,:,3].max()==0,(relative,'死亡残留')
        elif key=='goat':assert np.array(Image.open(source[-1]))[:,:,3].max()>0,(relative,'转阶段后主体不应消失')
        report.append({'form':key,'clip':clip,'frames':count,'fps':fps,'gif_seconds':milliseconds/1000,'edge_alpha':edge_peak})
        print(key,clip,count,'frames OK',flush=True)
for key in ['bat','snake','goat','goat_eye']:
    for width,height in [(1920,1080),(1280,720)]:assert Image.open(ROOT/f'outputs/boss-animation/stage/{key}-{width}.png').size==(width,height)
(ROOT/'build/boss-audit/delivery.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(len(report),'videos/GIFs verified; stage resolutions verified')
