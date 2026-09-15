"""从 BOSS 的 Spine 3.8 导出派生 4.3 资源；原始素材保持不变。

仅转换这四套素材用到的骨骼与加权 deform 时间线。旧版归一化贝塞尔
在生成阶段按 120 Hz 取样，保留原始关键时间和 stepped 边界。
"""
from pathlib import Path
import copy
import json
import math
import shutil
import argparse
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from motions import build_animations

GAME = Path(__file__).resolve().parents[2]
SOURCE = GAME.parent / 'Assets/BOSS'
OUT = GAME / 'assets/bosses/animation_studies'
AUDIT = GAME / 'build/boss-audit'
IDS = {'bat':'bat', 'snake':'snake', 'goat':'goat', 'goat_eye':'goat(real_style_eyeball)'}


def smooth(a, b, t):
    x = max(0., min(1., (t-a)/(b-a)))
    return x*x*(3-2*x)


def ease(k, u):
    curve = k.get('curve')
    if curve == 'stepped': return 0.
    if curve is None: return u
    points = curve if isinstance(curve, list) else [curve, k.get('c2',0),k.get('c3',1),k.get('c4',1)]
    x1,y1,x2,y2 = points
    def cubic(v,a,b): return 3*(1-v)**2*v*a + 3*(1-v)*v*v*b + v**3
    lo,hi=0.,1.
    for _ in range(22):
        m=(lo+hi)*.5
        if cubic(m,x1,x2)<u:lo=m
        else:hi=m
    return cubic((lo+hi)*.5,y1,y2)


def value(keys, t, fields, defaults, angle=False):
    if not keys or t < keys[0].get('time',0)-1e-8: return np.array(defaults,dtype=float)
    for i,k in enumerate(keys):
        if i+1==len(keys) or t<keys[i+1].get('time',0)-1e-8: break
    a=np.array([k.get(f,d) for f,d in zip(fields,defaults)],dtype=float)
    if i+1==len(keys):return a
    nxt=keys[i+1]; dt=nxt.get('time',0)-k.get('time',0)
    u=ease(k,(t-k.get('time',0))/dt)
    b=np.array([nxt.get(f,d) for f,d in zip(fields,defaults)],dtype=float)
    delta=b-a
    if angle:delta=(delta+180)%360-180
    return a+u*delta


def duration(tree):
    if isinstance(tree,dict): return max([float(tree.get('time',0))]+[duration(v) for v in tree.values()])
    if isinstance(tree,list): return max([0.]+[duration(v) for v in tree])
    return 0.


def sample_times(keys, end=None):
    end = duration(keys) if end is None else end
    ts={round(i/120,7) for i in range(math.ceil(end*120)+1) if i/120<=end}
    ts.update(float(k.get('time',0)) for k in keys)
    ts.add(end)
    # 阶跃前保留同值，不能被两侧线性插值抹平。
    for a,b in zip(keys,keys[1:]):
        if a.get('curve')=='stepped': ts.add(max(a.get('time',0),b.get('time',0)-.00001))
    return sorted(ts)


def convert(source):
    d=copy.deepcopy(source)
    d['skeleton']={'spine':'4.3.23',**{k:source['skeleton'][k] for k in ['x','y','width','height']}}
    for b in d['bones']:
        if 'transform' in b:b['inherit']=b.pop('transform')
    d['animations']={}
    for name,a in source['animations'].items():
        out={'bones':{}}
        for bone,tracks in a.get('bones',{}).items():
            dest={}
            for kind,keys in tracks.items():
                fields=['angle'] if kind=='rotate' else ['x','y']
                default=[0] if kind=='rotate' else ([1,1] if kind=='scale' else [0,0])
                converted=[]
                last=None
                for t in sample_times(keys):
                    vals=value(keys,t,fields,default,kind=='rotate')
                    if kind=='rotate':
                        if last is not None:vals[0]=last+(vals[0]-last+180)%360-180
                        last=vals[0]
                    converted.append({'time':t,**dict(zip(['value'] if kind=='rotate' else fields,[round(float(v),6) for v in vals]))})
                dest[kind]=converted
            out['bones'][bone]=dest
        if 'deform' in a:
            out['attachments']={}
            for skin,slots in a['deform'].items():
                out['attachments'][skin]={}
                for slot,attachments in slots.items():
                    out['attachments'][skin][slot]={}
                    for name2,keys in attachments.items():
                        n=max(k.get('offset',0)+len(k.get('vertices',[])) for k in keys)
                        full=[]
                        for k in keys:
                            f=copy.deepcopy(k); vs=[0.]*n
                            offset=f.get('offset',0);vs[offset:offset+len(f.get('vertices',[]))]=f.get('vertices',[])
                            f.update({str(i):v for i,v in enumerate(vs)});full.append(f)
                        out['attachments'][skin][slot][name2]={'deform':[{'time':t,'vertices':value(full,t,[str(i) for i in range(n)],[0]*n).round(6).tolist()} for t in sample_times(keys)]}
        d['animations'][name]=out
    return d


def atlas_parts(path, folder):
    lines=path.read_text(encoding='utf-8-sig').splitlines()
    page=Image.open(path.with_suffix('.png')).convert('RGBA')
    parts={}; current=None
    for line in lines:
        if not line.strip():continue
        if not line.startswith(' ') and ':' not in line:
            current=line
            if not line.endswith('.png'):parts[current]={}
        elif line.startswith(' ') and current in parts:
            k,v=line.strip().split(':',1);parts[current][k]=v.strip()
    (folder/'parts').mkdir(exist_ok=True)
    for i,(name,p) in enumerate(parts.items()):
        x,y=map(int,p['xy'].split(','));w,h=map(int,p['size'].split(','));rot=p['rotate']=='true'
        im=page.crop((x,y,x+(h if rot else w),y+(w if rot else h)))
        if rot:im=im.transpose(Image.Transpose.ROTATE_270)
        p['image']=im;p['index']=i
        im.save(folder/'parts'/f'{i:02d}.png')
    return parts


def matrices(bones, pose=None):
    worlds={};pose=pose or {}
    for b in bones:
        p=pose.get(b['name'],{})
        r=math.radians(b.get('rotation',0)+p.get('rotate',0));sx=b.get('scaleX',1)*p.get('sx',1);sy=b.get('scaleY',1)*p.get('sy',1)
        shx=math.radians(b.get('shearX',0)+p.get('shx',0));shy=math.radians(b.get('shearY',0)+p.get('shy',0))
        m=np.array([[math.cos(r+shx)*sx,-math.sin(r+shy)*sy,b.get('x',0)+p.get('x',0)],
                    [math.sin(r+shx)*sx, math.cos(r+shy)*sy,b.get('y',0)+p.get('y',0)],[0,0,1.]])
        worlds[b['name']]=worlds[b['parent']]@m if 'parent' in b else m
    return worlds


def mesh_points(a,bones,worlds):
    v=a['vertices']; points=[]; weights=[];cursor=0
    weighted=len(v)!=len(a['uvs'])
    for i in range(len(a['uvs'])//2):
        binds=[];p=np.zeros(2)
        if weighted:
            count=v[cursor];cursor+=1
            for _ in range(count):
                bi,x,y,w=v[cursor:cursor+4];cursor+=4
                p+=(worlds[bones[bi]['name']]@np.array([x,y,1]))[:2]*w
                binds.append({'bone':bones[bi]['name'],'point':[x,y],'weight':w})
        else:p=np.array(v[2*i:2*i+2])
        points.append(p);weights.append(binds)
    return np.array(points),weights


def write_resource(folder):
    root='res://'+folder.relative_to(GAME).as_posix()
    (folder/'boss.tres').write_text('[gd_resource type="SpineSkeletonDataResource" format=3]\n\n'
        f'[ext_resource type="SpineAtlasResource" path="{root}/boss.atlas" id="1"]\n'
        f'[ext_resource type="SpineSkeletonFileResource" path="{root}/boss.spine-json" id="2"]\n\n'
        '[resource]\natlas_res = ExtResource("1")\nskeleton_file_res = ExtResource("2")\n',encoding='utf-8')


def attach_effects(d, source, config, parts, folder, worlds):
    attachments=source['skins'][0]['attachments'];bones=source['bones']
    geometry={}
    for slot,ats in attachments.items():
        for name,a in ats.items():
            points,binds=mesh_points(a,bones,worlds)
            geometry[slot]=(a,points,binds,name)
    def anchor(screen, selected=None):
        target=np.array([(screen[0]-500)/config['unit']+config['center'][0],-((screen[1]-450)/config['unit']+config['center'][1])])
        best=None
        for slot,(a,points,binds,name) in geometry.items():
            if selected and selected not in slot:continue
            for j in range(0,len(a['triangles']),3):
                inds=a['triangles'][j:j+3];ps=points[inds]
                mat=np.vstack([ps.T,np.ones(3)])
                if abs(np.linalg.det(mat))<1e-8:continue
                bary=np.linalg.solve(mat,np.r_[target,1.]);penalty=float(max(0,-min(bary)))
                if best is None or penalty<best[0]:best=(penalty,slot,inds,bary,binds)
        _,slot,inds,bary,binds=best
        result=[]
        for index,w in zip(inds,bary):
            for bind in binds[index]:result.append({**bind,'weight':float(bind['weight']*w)})
        return {'slot':slot,'bindings':result,'reference':screen}
    if config['id']=='bat':
        config['lights']=[anchor((500,516),'92623'),anchor((318,548),'92939'),anchor((682,548),'92624')]
        for i,l in enumerate(config['lights']):l.update({'radius':230 if i==0 else 138,'delay':0 if i==0 else .10})
    elif config['id']=='snake':
        config['mouths']=[]
        # 喷口取上下唇之间，分别跟随两个加权附件；不能从上颚网格向嘴外远距离外推。
        mouth_landmarks=[
            (((414,268),'蛇_0002_'),((414,325),'蛇_0001_'),[-.2,-1],290,85,0),
            (((240,407),'0001s_0001'),((273,395),'0001s_0003'),[-1,.55],320,95,.12),
            (((717,287),'0000s_0002'),((692,356),'蛇_0003_'),[1,-.15],360,110,.24),
        ]
        for upper,lower,direction,length,width,delay in mouth_landmarks:
            a=anchor(*upper);b=anchor(*lower)
            a['reference']=[(upper[0][j]+lower[0][j])*.5 for j in range(2)]
            a['bindings']+=b['bindings']
            for bind in a['bindings']:bind['weight']*=.5
            for bind in a['bindings']:
                # 喷吐方向也保存为绑定骨骼局部向量，转头时与嘴部一起转动。
                v=np.linalg.solve(worlds[bind['bone']][:2,:2],np.array([direction[0],-direction[1]]))
                bind['direction']=[float(v[0]),float(-v[1])]
            a.update({'direction':direction,'length':length,'width':width,'delay':delay});config['mouths'].append(a)
    else:
        config['eyes']=[anchor((500,347),'0003_从选区'),anchor((432,394),'0004_已插入图像'),anchor((564,394),'0005_从选区')]
        eye_names=['拆羊_2_0003_从选区','拆羊_2_0004_已插入图像','拆羊_2_0005_从选区']
        new_slots=[];light_slots={}
        atlas=(folder/'boss.atlas').read_text(encoding='utf-8-sig')
        for slot in d['slots']:
            new_slots.append(slot)
            if slot['name'] not in eye_names:continue
            n=slot['name'];copy_name='eye_core_'+str(eye_names.index(n));p=parts[n]
            im=p['image'];mask=Image.new('RGBA',im.size,(255,255,255,255));mask.putalpha(im.getchannel('A'))
            mask.save(folder/(copy_name+'.png'))
            w,h=im.size;ow,oh=map(int,p['orig'].split(','));ox,oy=map(int,p['offset'].split(','))
            atlas+=f'\n{copy_name}.png\nsize: {w},{h}\nformat: RGBA8888\nfilter: Linear,Linear\nrepeat: none\n{copy_name}\n  rotate: false\n  xy: 0, 0\n  size: {w},{h}\n  orig: {ow},{oh}\n  offset: {ox},{oy}\n  index: -1\n'
            new_slots.append({'name':copy_name,'bone':slot['bone'],'attachment':copy_name,'color':'ffffff00'})
            a=copy.deepcopy(d['skins'][0]['attachments'][n][n]);a['path']=copy_name
            d['skins'][0]['attachments'][copy_name]={copy_name:a}
            for anim in d['animations'].values():
                if n in anim.get('attachments',{}).get('default',{}):
                    anim['attachments']['default'][copy_name]={copy_name:copy.deepcopy(anim['attachments']['default'][n][n])}
            light_slots[copy_name]={'alpha':[{'value':0.},{'time':1.,'value':1.}]}
        d['slots']=new_slots;d['animations']['eye_light']={'slots':light_slots}
        (folder/'boss.atlas').write_text(atlas,encoding='utf-8')


def build(key):
    p=next((SOURCE/IDS[key]).rglob('*.json')); source=json.loads(p.read_text(encoding='utf-8-sig'))
    folder=OUT/key;folder.mkdir(parents=True,exist_ok=True)
    parts=atlas_parts(p.with_suffix('.atlas'),folder)
    shutil.copy2(p.with_suffix('.png'),folder/'skeleton.png')
    shutil.copy2(p.with_suffix('.atlas'),folder/'boss.atlas')
    d=convert(source)
    sk=source['skeleton'];unit=560/max(sk['width'],sk['height'])
    config={'id':key,'unit':unit,'center':[sk['x']+sk['width']/2,-sk['y']-sk['height']/2],
            'idle':'feixing' if key=='bat' else 'animation','idle_duration':4.,'source':str(p.relative_to(GAME.parent)),
            'start':{'bat':.45,'snake':.55}.get(key,.6),'loop':1.2 if key=='bat' else 1.6,
            'end':{'bat':.55,'snake':.65}.get(key,.5),'hurt':{'bat':.38,'snake':.45}.get(key,.42),
            'death':{'bat':3.2,'snake':3.6}.get(key,7.0),'burst':{'bat':1.15,'snake':1.25}.get(key,4.8),
            'break':{'bat':1.45,'snake':1.65}.get(key,2.1)}
    if key.startswith('goat'):config['phase_break']=3.0
    _,worlds=build_animations(d,source,config,value,smooth,matrices)
    attach_effects(d,source,config,parts,folder,worlds)
    # 审看时隐藏原画槽，保留同一骨架上的眼罩；不能隐藏整棵 SpineSprite。
    d['animations']['body_visibility']={'slots':{
        slot['name']:{'alpha':[{'value':int(slot.get('color','ffffffff')[-2:],16)/255},{'time':1.,'value':0.}]}
        for slot in source['slots']}}
    (folder/'boss.spine-json').write_text(json.dumps(d,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    write_resource(folder)
    (folder/'animation.json').write_text(json.dumps(config,ensure_ascii=False,indent=2),encoding='utf-8')
    worlds=matrices(source['bones']); report=[]
    for b in source['bones']:
        pt=worlds[b['name']][:2,2];report.append({'bone':b['name'],'parent':b.get('parent'),'x':round(float(pt[0]),1),'y':round(float(pt[1]),1)})
    (AUDIT/(key+'-bones.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(key,len(d['bones']),'bones',list(d['animations']))


if __name__=='__main__':
    AUDIT.mkdir(parents=True,exist_ok=True)
    parser=argparse.ArgumentParser();parser.add_argument('--id',choices=list(IDS));args=parser.parse_args()
    selected=([args.id] if args.id else list(IDS))
    if any(k.startswith('goat') for k in selected):
        selected=list(dict.fromkeys(selected+['goat','goat_eye']))
    for key in selected:build(key)
    if 'goat' in selected:
        from goat_phases import merge_goat_skins
        merge_goat_skins(OUT, matrices)
