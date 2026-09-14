"""分界线素材归一化：原画水带、八个补绘姿势、运动补间及加权 Spine。

补绘整张生成，脚本只抠色、配准、运动补间和打包；不覆盖 edge.png。
Y 向下的图像坐标只在写 Spine 顶点时翻转一次。
"""
from pathlib import Path
import json
import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'assets/image/background/boundary_waves'
W,H,N = 384,256,128
ANCHOR=(280,232)
TIMES=np.array([0,.22,.40,.60,.69,.75,.86,1.])

def build_water_band():
    """保留原画完整水带，只将静态高浪压回低水脊，保住薄白浪缘。"""
    edge=np.array(Image.open(ROOT/'assets/image/background/edge.png').convert('RGBA'))
    # 原图远离水带的零星游离像素不属于连续底带。
    _,labels,stats,_=cv2.connectedComponentsWithStats((edge[:,:,3]>0).astype('uint8'))
    edge[labels!=1+np.argmax(stats[1:,cv2.CC_STAT_AREA]),3]=0
    yy,xx=np.mgrid[:edge.shape[0],:edge.shape[1]].astype('float32')
    source_y=yy.copy()
    # 源图坐标：连接点取自各浪根两侧的原画边缘。水带内部不压缩。
    for upper,spans in [(True,[(220,430,676,677),(500,770,679,666),(870,1020,669,678),(1110,1380,681,666)]),
                        (False,[(1270,1540,750,747),(1710,1890,748,755),(1970,2210,755,754),(2400,2510,740,746)])]:
        for left,right,start,end in spans:
            for x in range(left,right+1):
                t=(x-left)/(right-left);root=start+(end-start)*t
                occupied=np.flatnonzero(edge[:,x,3]>16)
                extent=root-occupied[0] if upper else occupied[-1]-root
                # 残留约 12 px 的原画水脊；两端连续回到原轮廓。
                scale=min(1.0,(12.0*np.sin(np.pi*t)+1.0)/max(extent,1.0))
                side=yy[:,x]<root if upper else yy[:,x]>root
                source_y[side,x]=root+(yy[side,x]-root)/scale
    # 预乘后重采样，避免透明边缘出现黑线；不改原 PNG。
    prem=edge.astype('float32')/255;prem[:,:,:3]*=prem[:,:,3:4]
    band=cv2.remap(prem,xx,source_y,cv2.INTER_LINEAR,borderMode=cv2.BORDER_CONSTANT)
    band[:,:,:3]/=np.maximum(band[:,:,3:4],.00001)
    Image.fromarray(np.rint(np.clip(band,0,1)*255).astype('uint8')).save(OUT/'water_band.png')
    from build_flow import build_flow
    build_flow()

def normalize():
    raw=np.array(Image.open(OUT/'source/keyposes-green.png').convert('RGB')).astype(float)
    # 去掉绿幕及边缘混色；原画的蓝紫和粉灰均远离此色域。
    a=1-np.clip((raw[:,:,1]-np.maximum(raw[:,:,0],raw[:,:,2]))/160,0,1)
    a[a<.12]=0
    rgb=raw.copy();rgb[:,:,1]=np.minimum(rgb[:,:,1],np.maximum(rgb[:,:,0],rgb[:,:,2])+8)
    rgba=np.dstack([rgb,a*255]).clip(0,255).astype('uint8')
    source=Image.fromarray(rgba)
    frames=[]
    (OUT/'keyposes').mkdir(parents=True,exist_ok=True)
    for i in range(8):
        x=[50,478,909,1336][i%4];y=[150,504][i//4]
        im=source.crop((x,y,x+396,y+250)).resize((W,243),Image.Resampling.LANCZOS)
        canvas=Image.new('RGBA',(W,H));canvas.paste(im,(0,0))
        pixels=np.array(canvas)
        # 水平切边融入底带，浪头保留完整不透明块面。
        yy,xx=np.mgrid[:H,:W]
        fade=np.clip(np.minimum(xx,W-1-xx)/24,0,1)*np.clip((231-yy)/17,0,1)
        pixels[:,:,3]=(pixels[:,:,3]*fade).astype('uint8')
        canvas=Image.fromarray(pixels);canvas.save(OUT/'keyposes'/f'{i:02}.png')
        frames.append(pixels.astype(np.float32)/255)
    build_water_band()
    return frames

def transitions(frames):
    """双向光流先搬运轮廓再混合，避免直接交叉淡化产生两个浪头。"""
    flows=[]
    for a,b in zip(frames,frames[1:]):
        def guide(im):
            # 空腔和浪缘同时参与匹配，底带锚点不动。
            return np.uint8((im[:,:,:3].mean(2)*.45+.55)*im[:,:,3]*255)
        g0,g1=guide(a),guide(b)
        flows.append((cv2.calcOpticalFlowFarneback(g0,g1,None,.5,5,35,5,7,1.5,0),
                      cv2.calcOpticalFlowFarneback(g1,g0,None,.5,5,35,5,7,1.5,0)))
    yy,xx=np.mgrid[:H,:W].astype('float32')
    # 关键形态间保持通过速度；旧逐段 smoothstep 会在每个姿势上刹停。
    # 非均匀时间节点的单调 Hermite 切线保留拍落时刻，并避免相位倒退。
    dt=np.diff(TIMES); speeds=1/dt; slopes=np.zeros(8)
    for k in range(1,7):
        w1=2*dt[k]+dt[k-1];w2=dt[k]+2*dt[k-1]
        slopes[k]=(w1+w2)/(w1/speeds[k-1]+w2/speeds[k])
    result=[]
    for i in range(N):
        t=i/(N-1); k=min(6,np.searchsorted(TIMES,t,side='right')-1)
        u=float((t-TIMES[k])/(TIMES[k+1]-TIMES[k]))
        u=float((u**3-2*u*u+u)*dt[k]*slopes[k]+(-2*u**3+3*u*u)+(u**3-u*u)*dt[k]*slopes[k+1])
        f,b=flows[k]
        # 预乘透明度补间，杜绝透明像素的黑/绿颜色渗入浪缘。
        def warp(im,flow,m):
            prem=im.copy();prem[:,:,:3]*=prem[:,:,3:4]
            return cv2.remap(prem,xx-flow[:,:,0]*m,yy-flow[:,:,1]*m,cv2.INTER_LINEAR,borderMode=cv2.BORDER_CONSTANT)
        mix=warp(frames[k],f,u)*(1-u)+warp(frames[k+1],b,1-u)*u
        mix[:,:,:3]/=np.maximum(mix[:,:,3:4],.0001)
        # 光流在骤变的空腔边缘可能匹配失败；去掉双向搬运留下的半透明重影。
        cover=np.clip((mix[:,:,3]-.58)/.025,0,1)
        mix[:,:,3]=cover*cover*(3-2*cover)
        result.append(Image.fromarray(np.uint8(np.clip(mix,0,1)*255)))
    return result

def mesh(path):
    nx,ny=12,8
    border=[(x,0) for x in range(nx+1)]+[(nx,y) for y in range(1,ny+1)]+[(x,ny) for x in range(nx-1,-1,-1)]+[(0,y) for y in range(ny-1,0,-1)]
    points=border+[(x,y) for y in range(ny+1) for x in range(nx+1) if (x,y) not in border]
    ids={p:i for i,p in enumerate(points)};uv=[];vertices=[];tri=[]
    origins=[(0,0),(-65,-55),(5,-145)]
    for x,y in points:
        px,py=x*W/nx-ANCHOR[0],y*H/ny-ANCHOR[1]
        uv.extend([x/nx,y/ny])
        top=np.clip(-py/180,0,1);lip=top*np.clip((px+100)/150,0,1)
        weights=[1-top,top-lip,lip];active=[(j,v) for j,v in enumerate(weights) if v>1e-5]
        vertices.append(len(active))
        for j,v in active:vertices.extend([j,round(px-origins[j][0],4),round(-(py-origins[j][1]),4),round(float(v),6)])
    for y in range(ny):
        for x in range(nx):
            a,b,c,d=[ids[p] for p in [(x,y),(x+1,y),(x,y+1),(x+1,y+1)]]
            tri.extend([a,c,b,b,c,d])
    return dict(type='mesh',path=path,width=W,height=H,uvs=uv,vertices=vertices,triangles=tri,hull=len(border))

def package(frames):
    atlas=Image.new('RGBA',(4096,4096));regions=[];attachments={};keys=[]
    (OUT/'parts').mkdir(exist_ok=True)
    for i,im in enumerate(frames):
        x=(i%10)*400+4;y=(i//10)*272+4;name=f'wave_{i:03}'
        im.save(OUT/'parts'/(name+'.png'))
        atlas.paste(im,(x,y));regions.append(f'{name}\nbounds:{x},{y},{W},{H}\n')
        attachments[name]=mesh(name);keys.append(dict(time=i/(N-1),name=name))
    atlas.save(OUT/'wave_atlas.png')
    (OUT/'wave.atlas').write_text('wave_atlas.png\nsize:4096,4096\nfilter:Linear,Linear\npma:false\n'+''.join(regions))
    # 浪身与薄浪唇分权重，余势由独立骨骼延迟，轮廓改变由补绘附件承担。
    bones=[dict(name='root'),dict(name='body',parent='root',x=-65,y=55),dict(name='lip',parent='root',x=5,y=145)]
    animation={'slots':{'water':{'attachment':keys}},'bones':{
        'body':{'rotate':[{'time':0,'value':0},{'time':.60,'value':-2},{'time':.75,'value':1},{'time':1,'value':0}]},
        'lip':{'translate':[{'time':0,'x':0,'y':0},{'time':.62,'x':3,'y':2},{'time':.74,'x':8,'y':-3},{'time':.81,'x':0,'y':-2},{'time':1,'x':0,'y':0}]}}}
    data={'skeleton':{'spine':'4.3.23','images':'parts/','width':W,'height':H},'bones':bones,
          'slots':[dict(name='water',bone='root',attachment='wave_000')],
          'skins':[{'name':'default','attachments':{'water':attachments}}],
          'animations':{'break':animation,'flow':{'bones':animation['bones']}}}
    (OUT/'wave.spine-json').write_text(json.dumps(data,separators=(',',':')))
    res='res://assets/image/background/boundary_waves/'
    (OUT/'wave.tres').write_text(f'[gd_resource type="SpineSkeletonDataResource" format=3]\n[ext_resource type="SpineAtlasResource" path="{res}wave.atlas" id="1"]\n[ext_resource type="SpineSkeletonFileResource" path="{res}wave.spine-json" id="2"]\n[resource]\natlas_res=ExtResource("1")\nskeleton_file_res=ExtResource("2")\n')
    # 离线短序列保留全部轮廓；正式播放固定首帧 UV，在 shader 中连续补间。
    lines=[f'[gd_resource type="SpriteFrames" load_steps={N+2} format=3]',f'[ext_resource type="Texture2D" path="{res}wave_atlas.png" id="1"]']
    for i in range(N):
        x=(i%10)*400+4;y=(i//10)*272+4
        lines.append(f'[sub_resource type="AtlasTexture" id="f{i}"]\natlas=ExtResource("1")\nregion=Rect2({x},{y},{W},{H})')
    lines+=['[resource]','animations=[{"name": &"wave", "loop":false, "speed":60.0, "frames":['+', '.join('{"duration":1.0,"texture":SubResource("f%d")}'%i for i in range(N))+']}]']
    (OUT/'small_frames.tres').write_text('\n'.join(lines))
    (OUT/'animation.json').write_text(json.dumps({'canvas':[W,H],'anchor':ANCHOR,'crash_phase':.75,'frames':N,'key_times':TIMES.tolist(),'source':'edge.png + source/keyposes-green.png'},indent=2))

if __name__=='__main__':
    import sys
    if '--band-only' in sys.argv:
        build_water_band();print('WATER BAND: original relief and white edges retained')
    else:
        frames=normalize();package(transitions(frames));print('WAVES: 8 keys, 128 attachments, 3 weighted bones, original water band')
