"""配准原画、提取燃烧分布并生成可平铺噪声；不修改输入原图。"""
from pathlib import Path
import json, shutil
import numpy as np
from PIL import Image

def gaussian_filter(values,sigma,mode='wrap'):
    # 周期频域滤波让噪声左右、上下接缝连续。
    squared=sum(f*f for f in np.meshgrid(*[np.fft.fftfreq(n) for n in values.shape],indexing='ij'))
    return np.fft.ifftn(np.fft.fftn(values)*np.exp(-2*np.pi**2*sigma**2*squared)).real

GAME=Path(__file__).resolve().parents[2]
OUT=GAME/'assets/ui/flame_frame'
SOURCES={'red':'F:/Temp/codex-clipboard-ad9712e1-cd88-4002-94da-7f21018a310c.png',
         'blue':'F:/Temp/codex-clipboard-519cf59b-b1c6-4dd3-99c2-c57e6afabce2.png'}

def build():
    OUT.mkdir(parents=True,exist_ok=True)
    meta={}
    for key,path in SOURCES.items():
        saved=OUT/(key+'_source.png')
        if not saved.exists():shutil.copy2(path,saved)
        im=Image.open(saved).convert('RGBA');box=im.getbbox();crop=im.crop(box)
        crop.save(OUT/(key+'_registered.png'));meta[key]={'source_size':im.size,'crop':box,'registered_size':crop.size}
    a=np.array(Image.open(OUT/'red_registered.png'),dtype=float)/255
    energy=a[:,:,:3].min(axis=2)*a[:,:,3];h,w=energy.shape
    # 四边亮芯的峰值限定燃烧根部，避开原图大面积柔晕。
    x0=int(np.argmax(energy[h//4:h*3//4,:w//3].sum(axis=0)))
    x1=int(w*2//3+np.argmax(energy[h//4:h*3//4,w*2//3:].sum(axis=0)))
    y0=int(np.argmax(energy[:h//4,w//3:w*2//3].sum(axis=1)))
    y1=int(h*3//4+np.argmax(energy[h*3//4:,w//3:w*2//3].sum(axis=1)))
    profiles=[energy[max(0,y0-24):y0+24,x0:x1].mean(axis=0),energy[y0:y1,x1-24:x1+24].mean(axis=1),
              energy[y1-24:y1+24,x0:x1].mean(axis=0),energy[y0:y1,max(0,x0-24):x0+24].mean(axis=1)]
    control=np.zeros((4,256,4),dtype=np.uint8)
    for i,p in enumerate(profiles):
        p=gaussian_filter(p,5);p=np.interp(np.linspace(0,len(p)-1,256),np.arange(len(p)),p)
        p=(p-p.min())/(np.ptp(p)+1e-6)
        control[i,:,0]=np.rint((.3+.7*p)*255);control[i,:,1]=np.arange(256);control[i,:,3]=255
    Image.fromarray(control).save(OUT/'fuel.png')
    rng=np.random.default_rng(4157);channels=[]
    for sigma in [10.,4.,1.4]:
        n=gaussian_filter(rng.normal(size=(256,256)),sigma,mode='wrap');n=(n-n.min())/np.ptp(n)
        channels.append(np.rint(n*255).astype(np.uint8))
    Image.fromarray(np.stack(channels+[np.full((256,256),255,dtype=np.uint8)],axis=2)).save(OUT/'noise.png')
    # 色阶保持原图白芯和彩色过渡；外围透明度由实时火形控制。
    for key,colors in {'red':[(84,34,86),(168,53,107),(246,114,59),(255,204,127),(255,252,237)],
                       'blue':[(28,57,115),(25,112,184),(20,224,245),(156,253,255),(244,255,255)]}.items():
        ramp=np.stack([np.interp(np.linspace(0,4,256),np.arange(5),np.array(colors)[:,c]) for c in range(3)],axis=1)
        Image.fromarray(np.rint(ramp).astype(np.uint8)[None,:,:]).save(OUT/(key+'_ramp.png'))
    meta['root_rect']=[x0,y0,x1,y1]
    old=np.array(Image.open(GAME/'assets/image/ui/选关/火框燃烧_8帧_透明PNG/火框燃烧_01.png').convert('RGBA'),dtype=float)/255
    e=old[:,:,:3].min(axis=2)*old[:,:,3];oh,ow=e.shape
    meta['old_root_rect']=[int(np.argmax(e[oh//4:oh*3//4,:ow//2].sum(axis=0))),int(np.argmax(e[:oh//4,ow//3:ow*2//3].sum(axis=1))),int(ow//2+np.argmax(e[oh//4:oh*3//4,ow//2:].sum(axis=0))),int(oh*3//4+np.argmax(e[oh*3//4:,ow//3:ow*2//3].sum(axis=1)))]
    (OUT/'source_registration.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Flame sources registered:',meta)

if __name__=='__main__':build()
