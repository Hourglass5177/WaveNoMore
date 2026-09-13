"""从六张原画中的彩色三张派生分件、加权 Spine 网格和动作；保留原文件。

运行：python tools/pet_animation/build_pets.py
坐标设计使用原图向下的 Y，写入 Spine 时转换为向上的 Y。
"""
from pathlib import Path
import argparse
import json
import math
import shutil
import numpy as np
from PIL import Image, ImageDraw

GAME = Path(__file__).resolve().parents[2]
SOURCE = GAME.parent / 'Assets' / '随从宠物原画'
OUT = GAME / 'assets' / 'pets' / 'animation_studies'
TAU = math.tau


def smooth(a, b, x):
    u = min(1., max(0., (x-a)/(b-a)))
    return u*u*(3-2*u)


def pulse(t, end, delay=0.):
    t -= delay
    return smooth(0., .18, t) * (1-smooth(.22, end-delay, t))


def wave(t, period, delay=0.):
    return math.sin(TAU*(t-delay)/period)-math.sin(-TAU*delay/period)


class Rig:
    def __init__(self, key, name, idle, trigger):
        self.key, self.name, self.idle, self.trigger = key, name, idle, trigger
        self.folder = OUT/key
        self.folder.mkdir(parents=True, exist_ok=True)
        self.image = Image.open(SOURCE/(name+'.png')).convert('RGBA')
        shutil.copy2(SOURCE/(name+'.png'), self.folder/'original.png')
        self.pixels = np.array(self.image)
        self.h, self.w = self.pixels.shape[:2]
        x0,y0,x1,y1 = self.image.getbbox()
        self.anchor = np.array([(x0+x1)/2,(y0+y1)/2])
        self.unit = 80/max(x1-x0,y1-y0)
        self.bones = [{'name':'root'}]
        self.origins = {'root':self.anchor}
        self.parents = {}
        self.parts = []

    def bone(self, name, p, parent='root'):
        p = np.array(p,dtype=float)
        delta = p-self.origins[parent]
        self.bones.append({'name':name,'parent':parent,'x':float(delta[0]),'y':float(-delta[1])})
        self.origins[name] = p
        self.parents[name] = parent

    def polygon(self, points):
        im=Image.new('1',self.image.size)
        ImageDraw.Draw(im).polygon(points,fill=1)
        return np.array(im,dtype=bool)

    def part(self, name, mask, weights, guard=0):
        rgba=self.pixels.copy()
        rgba[~mask]=0
        # 遮挡根部仅向原画内部延展；不改变外轮廓。后绘制的原始分件覆盖延展处。
        if guard:
            filled=mask & (rgba[:,:,3]>0)
            inside=self.pixels[:,:,3]>0
            for _ in range(guard):
                previous=rgba.copy(); valid=filled.copy()
                for dy,dx in [(0,1),(0,-1),(1,0),(-1,0)]:
                    neighbour=np.roll(np.roll(valid,dy,0),dx,1)
                    take=~filled & inside & neighbour
                    rgba[take]=np.roll(np.roll(previous,dy,0),dx,1)[take]
                    if name=='wool': rgba[take]=[218,201,202,255]
                    filled[take]=True
        part=Image.fromarray(rgba)
        box=part.getbbox()
        crop=part.crop(box)
        (self.folder/'parts').mkdir(exist_ok=True)
        crop.save(self.folder/'parts'/(name+'.png'))
        self.parts.append((name,crop,box,weights))

    def mesh(self, name, im, box, weights):
        width,height=im.size
        nx=max(2,math.ceil(width/24)); ny=max(2,math.ceil(height/24))
        # 边界顶点排在前面，Spine 编辑器可正确显示 hull；内部仍按规则网格三角化。
        grid=[(x,y) for y in range(ny+1) for x in range(nx+1)]
        border=[(x,0) for x in range(nx+1)]+[(nx,y) for y in range(1,ny+1)]+[(x,ny) for x in range(nx-1,-1,-1)]+[(0,y) for y in range(ny-1,0,-1)]
        points=border+[p for p in grid if p not in border]
        indices={p:i for i,p in enumerate(points)}
        uvs=[];vertices=[];triangles=[]
        bone_ids={b['name']:i for i,b in enumerate(self.bones)}
        for x,y in points:
            p=np.array([box[0]+width*x/nx,box[1]+height*y/ny])
            uvs.extend([x/nx,y/ny])
            influences={n:w for n,w in weights(*p).items() if w>1e-6}
            total=sum(influences.values())
            vertices.append(len(influences))
            for n,w in influences.items():
                local=p-self.origins[n]
                vertices.extend([bone_ids[n],round(float(local[0]),5),round(float(-local[1]),5),round(w/total,7)])
        for y in range(ny):
            for x in range(nx):
                a,b,c,d=[indices[p] for p in [(x,y),(x+1,y),(x,y+1),(x+1,y+1)]]
                for triangle in [(a,c,b),(b,c,d)]:
                    # 透明矩形角落不参与形变，裁掉无图像的三角面。
                    coverage=Image.new('1',im.size)
                    ImageDraw.Draw(coverage).polygon([(uvs[i*2]*width,uvs[i*2+1]*height) for i in triangle],fill=1)
                    if np.any(np.array(coverage)&(np.array(im.getchannel('A'))>0)):
                        triangles.extend(triangle)
        return {'type':'mesh','path':name,'width':width,'height':height,'uvs':uvs,'vertices':vertices,'triangles':triangles,'hull':len(border)}

    def write(self):
        # 单页图集，所有源分件另存 PNG，便于美术继续修订。
        atlas=Image.new('RGBA',(2048,2048))
        x=y=4;row=0;regions=[];attachments={};slots=[];chest=None
        for name,im,box,weight in self.parts:
            if x+im.width+4>2048: x=4;y+=row+4;row=0
            atlas.paste(im,(x,y))
            if self.key=='bat' and name=='body': chest=(x+235-box[0],y+290-box[1])
            regions.append(f'{name}\nbounds:{x},{y},{im.width},{im.height}\n')
            slots.append({'name':name,'bone':'root','attachment':name})
            attachments[name]={name:self.mesh(name,im,box,weight)}
            x+=im.width+4;row=max(row,im.height)
        used_h=2**math.ceil(math.log2(y+row+4))
        atlas=atlas.crop((0,0,2048,used_h));atlas.save(self.folder/'atlas.png')
        (self.folder/'pet.atlas').write_text(f'atlas.png\nsize:2048,{used_h}\nfilter:Linear,Linear\npma:false\n'+''.join(regions),encoding='utf-8')
        animations={}
        for clip,length in [('idle',self.idle),('trigger',self.trigger),('death',1.4)]:
            tracks={b['name']:{'rotate':[],'translate':[],'scale':[]} for b in self.bones}
            for frame in range(round(length*30)+1):
                t=frame/30
                pose=pose_at(self,clip,t)
                for name,timeline in tracks.items():
                    rotation,px,py,sx,sy=pose.get(name,(0,0,0,1,1))
                    timeline['rotate'].append({'time':t,'value':rotation})
                    timeline['translate'].append({'time':t,'x':px,'y':-py})
                    timeline['scale'].append({'time':t,'x':sx,'y':sy})
            animations[clip]={'bones':tracks}
        doc={'skeleton':{'spine':'4.3.23','images':'parts/','x':-self.w/2,'y':-self.h/2,'width':self.w,'height':self.h},'bones':self.bones,'slots':slots,'skins':[{'name':'default','attachments':attachments}],'animations':animations}
        (self.folder/'pet.spine-json').write_text(json.dumps(doc,separators=(',',':')),encoding='utf-8')
        (self.folder/'pet.tres').write_text('[gd_resource type="SpineSkeletonDataResource" format=3]\n\n[ext_resource type="SpineAtlasResource" path="res://assets/pets/animation_studies/'+self.key+'/pet.atlas" id="1"]\n[ext_resource type="SpineSkeletonFileResource" path="res://assets/pets/animation_studies/'+self.key+'/pet.spine-json" id="2"]\n\n[resource]\natlas_res = ExtResource("1")\nskeleton_file_res = ExtResource("2")\n',encoding='utf-8')
        meta={'id':self.key,'name':self.name,'unit_scale':self.unit,'source_anchor':self.anchor.tolist(),'idle':self.idle,'trigger':self.trigger,'death':2.05,'bone_death':1.4,'bone_count':len(self.bones),'parts':[p[0] for p in self.parts]}
        if chest: meta['highlight_region']=[chest[0]/2048,chest[1]/used_h,38/2048,42/used_h]
        if self.key=='snake':
            meta['breath']=[]
            # 火焰与嘴部使用同一组网格权重，避免抬头时从颈骨原点冒火。
            for part,point,direction,start,length in [
                ('neck_middle',(338,217),(.20,.98),.18,8),
                ('neck_right',(522,217),(1.,-.04),.26,10),
                ('neck_left',(119,394),(-.72,.69),.32,9)]:
                weights=next(p[3] for p in self.parts if p[0]==part)(*point)
                binds=[{'bone':n,'weight':w,'point':(np.array(point)-self.origins[n]).tolist()}
                       for n,w in weights.items() if w>1e-6]
                meta['breath'].append({'bindings':binds,'direction':direction,'start':start,'duration':.44,'length_px':length})
        (self.folder/'animation.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
        print(self.key,len(self.bones),'bones',len(self.parts),'parts')


def blend(root, name, factor, tip=None, tip_factor=0):
    factor=min(1.,max(0.,factor)); tip_factor=min(1.,max(0.,tip_factor))
    result={root:1-factor,name:factor*(1-tip_factor)}
    if tip:result[tip]=factor*tip_factor
    return result


def bat():
    r=Rig('bat','蝠漆漆',1.2,.6)
    for n,p,parent in [('wing_l',(149,278),'root'),('tip_l',(99,335),'wing_l'),('wing_r',(322,254),'root'),('tip_r',(383,320),'wing_r'),('ear_l',(143,174),'root'),('ear_r',(255,157),'root'),('tail',(254,354),'root')]: r.bone(n,p,parent)
    yy,xx=np.mgrid[:r.h,:r.w]
    left=(xx<151)&(yy>267);right=(xx>319)&(yy>232)
    ear_l=(xx<166)&(yy<170);ear_r=(xx>220)&(yy<159)
    tail=(yy>351)&(xx>224)&(xx<296)
    body=~(left|right|ear_l|ear_r|tail)
    # 翼根固定，向下远离翼根的薄膜也交给翼骨，避免收翼时被身体权重拽成反折。
    r.part('wing_l',left,lambda x,y:blend('root','wing_l',max(smooth(150,75,x),smooth(278,337,y)),'tip_l',smooth(300,420,y)))
    r.part('wing_r',right,lambda x,y:blend('root','wing_r',max(smooth(320,385,x),smooth(254,322,y)),'tip_r',smooth(285,398,y)))
    r.part('ear_l',ear_l,lambda x,y:blend('root','ear_l',smooth(170,80,y)))
    r.part('ear_r',ear_r,lambda x,y:blend('root','ear_r',smooth(160,70,y)))
    r.part('tail',tail,lambda x,y:blend('root','tail',smooth(352,400,y)))
    r.part('body',body,lambda x,y:{'root':1})
    return r


def snake():
    r=Rig('snake','苹果蛇',3.2,.8)
    for n,p in [('neck_middle',(251,307)),('head_middle',(275,225)),('neck_right',(396,424)),('head_right',(448,247)),('neck_left',(260,325)),('head_left',(158,337)),('coil',(419,513)),('tail',(253,582)),('tail_tip',(150,663))]:
        parent={'head_middle':'neck_middle','head_right':'neck_right','head_left':'neck_left','tail_tip':'tail'}.get(n,'root');r.bone(n,p,parent)
    yy,xx=np.mgrid[:r.h,:r.w]
    middle=(yy<286)&(xx<371)&(xx>202)
    right=r.polygon([(342,332),(343,270),(400,165),(556,145),(555,285),(437,354),(453,427),(400,427),(366,392)]) & ~middle
    left=(xx<221)&(yy<409)&~middle
    body=~(middle|right|left)
    # 中颈的权重过渡稍长，让加大的低头动作沿整段弯曲，不挤在颈根。
    r.part('neck_middle',middle,lambda x,y:blend('root','neck_middle',smooth(288,215,y),'head_middle',smooth(249,195,y)))
    r.part('neck_right',right,lambda x,y:blend('root','neck_right',smooth(428,330,y),'head_right',smooth(304,240,y)))
    r.part('body',body,lambda x,y:snake_body_weights(x,y))
    r.part('neck_left',left,lambda x,y:blend('root','neck_left',smooth(222,170,x),'head_left',smooth(195,150,x)))
    return r


def snake_body_weights(x,y):
    if x<310 and y>515:
        return blend('root','tail',smooth(319,200,x),'tail_tip',smooth(595,727,y))
    return blend('root','coil',smooth(450,575,y)*smooth(300,455,x))


def sheep():
    r=Rig('sheep','羊头仔',3.6,.6)
    for n,p in [('head',(270,290)),('wool',(265,325)),('hand_l',(218,387)),('hand_r',(382,340)),('tuft',(219,430))]:r.bone(n,p)
    yy,xx=np.mgrid[:r.h,:r.w];rgb=r.pixels[:,:,:3].astype(float)
    # 按原画颜色区分角与面部、绒毛，保留细碎笔触。头部黑眼睛通过包围区域一同归入。
    head_region=r.polygon([(22,79),(205,60),(305,23),(435,52),(452,210),(373,222),(345,342),(309,351),(207,317),(142,270),(12,278)])
    face=r.polygon([(173,172),(247,108),(305,126),(361,168),(365,271),(320,338),(193,286),(153,242)])
    head=(yy<215) | ((xx<172)&(yy<275)) | (head_region & ((rgb[:,:,0]>rgb[:,:,1]*1.09)|face))
    hand_l=(yy>380)&(xx>207)&(xx<296)&(rgb.max(axis=2)<175)
    hand_r=(yy>334)&(xx>346)&(rgb.max(axis=2)<175)
    tuft=(yy>440)&(xx<236)&~hand_l
    wool=~(head|hand_l|hand_r|tuft)
    r.part('wool',wool,lambda x,y:blend('root','wool',smooth(220,390,y)),guard=9)
    r.part('tuft',tuft,lambda x,y:{'tuft':1})
    r.part('hand_l',hand_l,lambda x,y:blend('root','hand_l',smooth(380,421,y)))
    r.part('hand_r',hand_r,lambda x,y:blend('root','hand_r',smooth(334,380,y)))
    r.part('head',head,lambda x,y:{'head':1})
    return r


def pose_at(r, clip, t):
    pose={}
    def put(n,rot=0,x=0,y=0,sx=1,sy=1):pose[n]=(rot,x/r.unit,y/r.unit,sx,sy)
    if clip=='idle':
        if r.key=='bat':
            # 下拍占 38%，回翼较慢；余弦端点令位置和速度连续。
            def flap(v):
                phase=(v%1.2)/1.2
                u=phase/.62 if phase<.62 else 1+(phase-.62)/.38
                return math.cos(math.pi*u)-1
            f=flap(t)
            put('root',y=2*math.sin(TAU*t/1.2))
            for side,s in [('l',1),('r',-1)]:
                put('wing_'+side,rot=s*14*f)
                put('tip_'+side,rot=s*5*(flap(t-.07)-flap(-.07)))
                put('ear_'+side,rot=s*2*wave(t,1.2,.12))
            put('tail',rot=4*wave(t,1.2,.15))
        elif r.key=='snake':
            # 三首先后摆动，尾尖再跟随；放大局部弧线而不是整体缩放原画。
            for n,delay,s in [('middle',0,1),('right',.12,-1),('left',.24,1)]:
                v=wave(t,3.2,delay)
                put('neck_'+n,rot=4.2*v)
                put('head_'+n,rot=-2.1*v)
            put('coil',rot=1.8*wave(t,3.2,.25))
            put('tail',rot=4.6*wave(t,3.2,.4))
            put('tail_tip',rot=8*wave(t,3.2,.6))
        else:
            put('root',y=2.5*math.sin(TAU*t/3.6))
            put('head',rot=2*math.sin(TAU*t/3.6))
            put('wool',rot=.5*wave(t,3.6,.12),sx=1+.012*math.sin(TAU*t/3.6),sy=1-.006*math.sin(TAU*t/3.6))
            put('hand_l',rot=5*wave(t,3.6,.18));put('hand_r',rot=-4*wave(t,3.6,.22))
            put('tuft',x=.35*wave(t,3.6,.3),y=.5*wave(t,3.6,.3))
    elif clip=='trigger':
        e=pulse(t,r.trigger)
        prep=math.sin(math.pi*min(t/.1,1)) if t<.1 else 0
        if r.key=='bat':
            e=smooth(.10,.23,t)*(1-smooth(.26,.6,t))
            put('root',y=.7*prep-3*e)
            for side,s in [('l',1),('r',-1)]:
                put('wing_'+side,rot=s*(6*prep-38*e))
                put('tip_'+side,rot=-s*8*pulse(t,.6,.04))
                put('ear_'+side,rot=s*3*pulse(t,.6,.06))
            put('tail',rot=5*pulse(t,.6,.09))
        elif r.key=='snake':
            for n,delay,s in [('middle',0,1),('right',.08,1),('left',.14,-1)]:
                env=pulse(t,.8,delay)
                put('neck_'+n,rot=s*10*env,y=-3.3*env)
                put('head_'+n,rot=-s*3.5*env)
            put('coil',rot=-3*e);put('tail',rot=-8*pulse(t,.8,.06));put('tail_tip',rot=13*pulse(t,.8,.12))
        else:
            put('head',rot=-3*e,y=.8*e)
            put('hand_l',rot=18*e,x=1.0*e,y=-1.6*e)
            put('hand_r',rot=-21*e,x=-1.2*e,y=-1.2*e)
            release=pulse(t,.6,.10)
            put('wool',sx=1+.025*release,sy=1-.012*release)
            put('tuft',y=-.8*pulse(t,.6,.06))
    else:
        sink=smooth(.1,1.2,t); put('root',rot=-3*sink if r.key=='bat' else 0,y=6*sink)
        if r.key=='bat':
            for side,s in [('l',1),('r',-1)]:
                put('wing_'+side,rot=s*23*smooth(.05,.9,t))
                put('tip_'+side,rot=s*9*smooth(.18,1.12,t))
                put('ear_'+side,rot=s*11*smooth(.2,1.1,t))
            put('tail',rot=-10*smooth(.3,1.2,t))
        elif r.key=='snake':
            put('root',y=8*sink)
            for n,delay,s in [('middle',0,-1),('right',.1,-1),('left',.2,1)]:
                e=smooth(.05+delay,.95+delay,t)
                # 中颈短而宽，用弯曲表现低垂，少作纵向压缩，避免腹纹挤成一线。
                put('neck_'+n,rot=s*(14 if n=='middle' else 17)*e,y=(.5 if n=='middle' else 2.4)*e)
                put('head_'+n,rot=s*(10 if n=='middle' else 12)*e)
            put('coil',rot=-3.5*sink);put('tail',rot=-12*smooth(.2,1.2,t));put('tail_tip',rot=-25*smooth(.35,1.2,t))
        else:
            put('head',rot=-9*smooth(.06,.95,t),y=1.4*sink)
            put('hand_l',rot=-9*sink);put('hand_r',rot=8*sink)
            put('wool',sx=1-.02*sink,sy=1-.045*sink)
            put('tuft',y=1.5*smooth(.3,1.2,t))
    return pose


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pet',choices=['bat','snake','sheep'])
    selected=parser.parse_args().pet
    for key,factory in [('bat',bat),('snake',snake),('sheep',sheep)]:
        if selected is None or key==selected: factory().write()
