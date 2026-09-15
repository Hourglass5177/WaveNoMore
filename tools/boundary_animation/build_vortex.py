"""厚浪卷入：补绘形态生成独立 Spine 附件，中央底带由分流水脚接替。"""
from pathlib import Path
import json
import numpy as np
from PIL import Image
import build_waves

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/image/background/boundary_vortex'
W,H,N=384,256,128
ANCHOR=(288,192)
TIMES=np.array([0,.15,.27,.38,.48,.58,.70,1.0])

def keys():
    raw=np.array(Image.open(OUT/'source/rising-profile-green.png').convert('RGB')).astype(float)
    a=1-np.clip((raw[:,:,1]-np.maximum(raw[:,:,0],raw[:,:,2]))/160,0,1)
    a[a<.12]=0
    raw[:,:,1]=np.minimum(raw[:,:,1],np.maximum(raw[:,:,0],raw[:,:,2])+6)
    im=Image.fromarray(np.uint8(np.dstack([raw,a*255]).clip(0,255)))
    cw,ch=im.width/4,im.height/2
    (OUT/'keyposes').mkdir(exist_ok=True)
    result=[]
    for i in range(8):
        pose=i
        source=im.crop((round(pose%4*cw),round(pose//4*ch),round((pose%4+1)*cw),round((pose//4+1)*ch)))
        # 全部使用同一水面基准和比例；末两帧只收尽，不反向配准浪头。
        source=source.resize((376,248),Image.Resampling.LANCZOS)
        canvas=Image.new('RGBA',(W,H));canvas.paste(source,(4,-22))
        pixels=np.array(canvas)
        Image.fromarray(pixels).save(OUT/'keyposes'/f'{i:02}.png')
        result.append(pixels.astype(np.float32)/255)
    return result

def mesh(name):
    nx,ny=24,24
    border=[(x,0) for x in range(nx+1)]+[(nx,y) for y in range(1,ny+1)]+[(x,ny) for x in range(nx-1,-1,-1)]+[(0,y) for y in range(ny-1,0,-1)]
    points=border+[(x,y) for y in range(ny+1) for x in range(nx+1) if (x,y) not in border]
    ids={p:i for i,p in enumerate(points)};uv=[];vertices=[];tri=[]
    origins=[(0,0),(-95,80),(15,130),(95,-80),(-15,-130)]
    for x,y in points:
        px,py=x*576/nx-ANCHOR[0],ANCHOR[1]-y*384/ny
        uv.extend([x/nx,y/ny])
        crest=float(np.clip(abs(py)/110,0,1))*.8
        lip=float(np.clip(((px if py>=0 else -px)+80)/160,0,1))
        weights=[1-crest,crest*(1-lip) if py>=0 else 0,crest*lip if py>=0 else 0,crest*(1-lip) if py<0 else 0,crest*lip if py<0 else 0]
        active=[(i,w) for i,w in enumerate(weights) if w>1e-6];vertices.append(len(active))
        for i,w in active:vertices.extend([i,round(px-origins[i][0],5),round(py-origins[i][1],5),round(w,6)])
    for y in range(ny):
        for x in range(nx):
            a,b,c,d=[ids[p] for p in [(x,y),(x+1,y),(x,y+1),(x+1,y+1)]]
            tri.extend([a,c,b,b,c,d])
    return dict(type='mesh',path=name,width=W,height=H,uvs=uv,vertices=vertices,triangles=tri,hull=len(border))

def build():
    frames=keys()
    # 复用已在小浪中验证的双向轮廓补间，仅更换本次独立画布与时间节点。
    build_waves.W,build_waves.H,build_waves.N=W,H,N;build_waves.TIMES=TIMES
    images=build_waves.transitions(frames)
    # 轮廓补间会收紧透明覆盖；连接渐变必须在其后处理，否则被截成硬边。
    yy,xx=np.mgrid[:H,:W]
    fade=np.clip(np.minimum(xx-3,W-4-xx)/50,0,1)
    fade=fade*fade*(3-2*fade)
    for i,im in enumerate(images):
        pixels=np.array(im);pixels[:,:,3]=np.uint8(pixels[:,:,3]*fade)
        images[i]=Image.fromarray(pixels)
    atlas=Image.new('RGBA',(4096,4096));regions=[];attachments={};timeline=[]
    parts=OUT/'parts';parts.mkdir(exist_ok=True);(parts/'.gdignore').touch()
    for i,im in enumerate(images):
        x=i%10*400+4;y=i//10*272+4;name=f'vortex_{i:03}'
        im.save(parts/f'{name}.png');atlas.paste(im,(x,y))
        regions.append(f'{name}\nbounds:{x},{y},{W},{H}\n')
        attachments[name]=mesh(name);timeline.append({'time':i/(N-1),'name':name})
    atlas.save(OUT/'vortex_atlas.png')
    (OUT/'vortex.atlas').write_text('vortex_atlas.png\nsize:4096,4096\nfilter:Linear,Linear\npma:false\n'+''.join(regions))
    bones=[dict(name='root')]+[dict(name=name,parent='root',x=x,y=y) for name,x,y in [('body_up',-95,80),('crest_up',15,130),('body_down',95,-80),('crest_down',-15,-130)]]
    tracks={}
    for bone,offset,amplitude in [('body_up',0,1.0),('crest_up',.028,1.5),('body_down',0,1.0),('crest_down',.028,1.5)]:
        tracks[bone]={'rotate':[{'time':float(t),'value':float(np.sin(np.clip((t-offset)/.96,0,1)*np.pi*2)*amplitude)} for t in np.linspace(0,1,65)]}
    data={'skeleton':{'spine':'4.3.23','images':'parts/','width':W,'height':H},'bones':bones,
          'slots':[dict(name='water',bone='root',attachment='vortex_000')],
          'skins':[dict(name='default',attachments={'water':attachments})],
          'animations':{'vortex':{'slots':{'water':{'attachment':timeline}},'bones':tracks},'flow':{'bones':tracks}}}
    (OUT/'vortex.spine-json').write_text(json.dumps(data,separators=(',',':')))
    res='res://assets/image/background/boundary_vortex/'
    (OUT/'vortex.tres').write_text(f'[gd_resource type="SpineSkeletonDataResource" format=3]\n[ext_resource type="SpineAtlasResource" path="{res}vortex.atlas" id="1"]\n[ext_resource type="SpineSkeletonFileResource" path="{res}vortex.spine-json" id="2"]\n[resource]\natlas_res=ExtResource("1")\nskeleton_file_res=ExtResource("2")\n')
    (OUT/'animation.json').write_text(json.dumps({'canvas':[W,H],'design_canvas':[576,384],'anchor':ANCHOR,'key_times':TIMES.tolist(),'frames':N,'style':'单股细纹卷臂，运行时中心对称配对','source':'source/rising-profile-green.png'},ensure_ascii=False,indent=2),encoding='utf-8')
    # 中央原来横穿判定圈的底带由新图的分流水脚接替；其余底带像素不变。
    band=np.array(Image.open(ROOT/'assets/image/background/boundary_waves/water_band.png'))
    distance=abs((np.arange(band.shape[1])-1325)*.7616555803103707)
    fade=np.clip((distance-175)/90,0,1);fade=fade*fade*(3-2*fade)
    band[:,:,3]=np.uint8(np.rint(band[:,:,3]*fade[None,:]))
    Image.fromarray(band).save(OUT/'water_band_split.png')
    print('VORTEX: 128 single-arm silhouettes, 5 weighted bones; paired by runtime rotation')

if __name__=='__main__':build()
