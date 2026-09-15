"""羊头双皮肤、额眼表层分片与共同裂解几何。只生成派生资源。"""
import copy
import json
import math
import shutil
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

EYE='拆羊_2_0003_从选区'

def smooth(a,b,t):
    u=max(0.,min(1.,(t-a)/(b-a)));return u*u*(3-2*u)

def merge_goat_skins(root, matrices):
    ids=['goat','goat_eye']
    rigs={k:json.loads((root/k/'boss.spine-json').read_text(encoding='utf-8')) for k in ids}
    rig=copy.deepcopy(rigs['goat'])
    # 两形态保留各自 UV/三角形；图集区名加前缀，避免同名附件误取另一页。
    pages={};atlas=[];skins=[]
    for key,d in rigs.items():
        lines=(root/key/'boss.atlas').read_text(encoding='utf-8').splitlines()
        for line in lines:
            if line and not line[0].isspace() and ':' not in line:
                if line.endswith('.png'):
                    pages[key+'_'+line]=root/key/line
                    line=key+'_'+line
                else:line=key+'/'+line
            atlas.append(line)
        atlas.append('')
        skin=copy.deepcopy(d['skins'][0]);skin['name']=key
        for slot,ats in skin['attachments'].items():
            for name,a in ats.items():a['path']=key+'/'+a.get('path',name)
        skins.append(skin)
    rig['skins']=skins
    for name,anim in rig['animations'].items():
        attachments={}
        for key,d in rigs.items():
            original=d['animations'].get(name,{}).get('attachments',{}).get('default',{})
            if original:attachments[key]=copy.deepcopy(original)
        if attachments:anim['attachments']=attachments
        else:anim.pop('attachments',None)
    # 六片表层共享原图，新增子骨骼让剥落围绕各片中心，而非围绕整个额眼旋转。
    original=copy.deepcopy(skins[0]['attachments'][EYE][EYE])
    v=original['vertices'];local=[];cursor=0
    for _ in original['uvs'][::2]:
        count=v[cursor];assert count==1;local.append(v[cursor+2:cursor+4]);cursor+=1+count*4
    local=np.array(local);uv=np.array(original['uvs']).reshape(-1,2)
    seeds=np.array([[.25,.22],[.70,.18],[.16,.60],[.50,.48],[.82,.58],[.5,.86]])
    buckets=[[] for _ in seeds]
    for tri in np.array(original['triangles']).reshape(-1,3):
        i=np.argmin(((seeds-uv[tri].mean(axis=0))**2).sum(axis=1));buckets[i].extend(map(int,tri))
    base={}
    for name,timelines in rig['animations']['phase_break']['bones'].items():
        base[name]={'rotate':timelines['rotate'][0]['value'],'x':timelines['translate'][0]['x'],'y':timelines['translate'][0]['y'],
                    'sx':timelines['scale'][0]['x'],'sy':timelines['scale'][0]['y']}
        base[name].update({'shx':timelines.get('shear',[{}])[0].get('x',0),'shy':timelines.get('shear',[{}])[0].get('y',0)})
    world=matrices(rig['bones'],base)['bone4'][:2,:2]
    unit=json.loads((root/'goat/animation.json').read_text(encoding='utf-8'))['unit']
    insert=next(i for i,s in enumerate(rig['slots']) if s['name']==EYE)+1
    seal_names=[]
    for i,triangles in enumerate(buckets):
        if not triangles:continue
        name=f'seal_{i}';seal_names.append(name)
        center=local[list(set(triangles))].mean(axis=0)
        bone_index=len(rig['bones']);rig['bones'].append({'name':name,'parent':'bone4','x':float(center[0]),'y':float(center[1])})
        piece=copy.deepcopy(original);piece['triangles']=triangles;piece.pop('edges',None)
        vertices=[]
        for xy in local:vertices.extend([1,bone_index,float(xy[0]-center[0]),float(xy[1]-center[1]),1.])
        piece['vertices']=vertices
        rig['slots'].insert(insert,{'name':name,'bone':name,'attachment':name,'color':'ffffff00'});insert+=1
        for skin in skins:skin['attachments'][name]={name:copy.deepcopy(piece)}
        screen=world@(center-local.mean(axis=0))*unit
        dx=(1 if screen[0]>=0 else -1)*(25+abs(screen[0])*.3);dy=-18-abs(screen[0])*.35
        delta=np.linalg.solve(world,np.array([dx,dy])/unit)
        for anim_name,anim in rig['animations'].items():
            if anim_name in ['eye_light','body_visibility']:continue
            anim.setdefault('bones',{})[name]={'rotate':[{'value':0.}],'translate':[{'x':0.,'y':0.}]}
            anim.setdefault('slots',{})[name]={'alpha':[{'value':0.}]}
        frames={'rotate':[],'translate':[]};alpha=[]
        for f in range(181):
            t=f/60.;u=smooth(1.05+i*.025,1.85,t);drop=smooth(1.60,1.85,t)
            frames['translate'].append({'time':t,'x':float(delta[0]*u),'y':float(delta[1]*u)})
            frames['rotate'].append({'time':t,'value':(1 if screen[0]>0 else -1)*30*u})
            alpha.append({'time':t,'value':1-drop})
        rig['animations']['phase_break']['bones'][name]=frames
        rig['animations']['phase_break']['slots'][name]={'alpha':alpha}
    # 真实额眼按原网格修形，揭露后停住凝视，再接回常态相位。
    source=rigs['goat_eye']['animations']['animation'].get('attachments',{}).get('default',{})
    # 只修形虹膜附近的顶点，眼白外缘保持原位；原导出的额眼 deform 本身是定姿。
    real=skins[1]['attachments'][EYE][EYE]
    real_uv=np.array(real['uvs']).reshape(-1,2)
    real_xy=np.array(real['vertices']).reshape(-1,5)[:,2:4]
    iris=np.array([.50,.50]);radius=np.linalg.norm(real_uv-iris,axis=1)
    support=np.array([1-smooth(.16,.38,float(r)) for r in radius])
    center=real_xy[np.argmin(radius)]
    native=source[EYE][EYE]['deform'][0]
    baseline=np.zeros(real_xy.size);offset=native.get('offset',0);baseline[offset:offset+len(native.get('vertices',[]))]=native.get('vertices',[])
    for clip,duration in [('phase_break',3.),('death',7.)]:
        frames=[]
        for frame in range(round(duration*60)+1):
            t=frame/60.
            if clip=='phase_break':
                contract=.16*smooth(1.95,2.25,t)*(1-smooth(2.65,3.,t))
                gaze=-3.*smooth(1.85,2.06,t)*(1-smooth(2.06,2.25,t))
            else:contract=.24*smooth(.15,.7,t);gaze=0.
            delta=-(real_xy-center)*support[:,None]*contract
            delta+=np.linalg.solve(world,np.array([gaze,0.])/unit)[None,:]*support[:,None]
            frames.append({'time':t,'vertices':np.round(baseline+delta.ravel(),6).tolist()})
        slots=rig['animations'][clip].setdefault('attachments',{}).setdefault('goat_eye',{})
        for name in [EYE,'eye_core_0']:slots[name]={name:{'deform':copy.deepcopy(frames)}}
    # 让手动素材隐藏仍可覆盖两种皮肤及新增薄片。
    for n in seal_names:rig['animations']['body_visibility']['slots'][n]={'alpha':[{'value':0.},{'time':1.,'value':0.}]}
    rig['animations']['seal_reveal']={'slots':{n:copy.deepcopy(rig['animations']['phase_break']['slots'][n]) for n in seal_names}}
    # 额眼表层的裂光与六片实际边界一致，透明区不参与发光。
    old_atlas=(root/'goat'/'boss.atlas').read_text(encoding='utf-8')
    entry=old_atlas.split('\neye_core_0\n',1)[1].split('\n\n',1)[0]
    metadata=dict(line.strip().split(':',1) for line in entry.splitlines() if ':' in line)
    ow,oh=map(int,metadata['orig'].split(','));ox,oy=map(int,metadata['offset'].split(','))
    mask=Image.open(root/'goat'/'eye_core_0.png').convert('RGBA');w,h=mask.size
    crack=Image.new('RGBA',(w,h),(255,223,153,0));draw=ImageDraw.Draw(crack)
    edges={}
    for group,triangles in enumerate(buckets):
        for tri in np.array(triangles).reshape(-1,3):
            for a,b in zip(tri,np.roll(tri,-1)):edges.setdefault(tuple(sorted((int(a),int(b)))),set()).add(group)
    for (a,b),groups in edges.items():
        if len(groups)>1:
            points=[(uv[j,0]*ow-ox,uv[j,1]*oh-(oh-h-oy)) for j in [a,b]]
            draw.line(points,fill=(255,233,176,230),width=4)
    pixels=np.array(crack);pixels[:,:,3]=(pixels[:,:,3].astype(float)*np.array(mask)[:,:,3]/255).astype(np.uint8)
    crack=Image.fromarray(pixels)
    import io
    buf=io.BytesIO();crack.save(buf,format='PNG')
    raw_crack=buf.getvalue()
    atlas.extend(['','seal_crack.png',f'size: {w},{h}','format: RGBA8888','filter: Linear,Linear','repeat: none','seal_crack',entry])
    rig['slots'].insert(insert,{'name':'seal_crack','bone':'bone4','attachment':'seal_crack','color':'ffffff00'})
    for skin in skins:
        attachment=copy.deepcopy(original);attachment['path']='seal_crack'
        skin['attachments']['seal_crack']={'seal_crack':attachment}
    rig['animations']['seal_reveal']['slots']['seal_crack']={'alpha':[{'value':0.},{'time':.45,'value':0.},{'time':1.05,'value':.75},{'time':1.65,'value':0.}]}
    # 页源先读入内存，防止目标路径恰为另一形态的源时覆盖。
    raw={n:p.read_bytes() for n,p in pages.items()}
    raw['seal_crack.png']=raw_crack
    # 觉醒时两侧眼睛使用纯白亮层，额眼继续显示真实虹膜；攻击原有亮层独立保留。
    awaken={}
    for i in [1,2]:
        name=f'eye_awaken_{i}';original_name=f'eye_core_{i}'
        entry=old_atlas.split('\n'+original_name+'\n',1)[1].split('\n\n',1)[0]
        im=Image.open(root/'goat'/(original_name+'.png')).convert('RGBA')
        white=Image.new('RGBA',im.size,'white');white.putalpha(im.getchannel('A'));buf=io.BytesIO();white.save(buf,format='PNG');raw[name+'.png']=buf.getvalue()
        atlas.extend(['',name+'.png',f'size: {im.width},{im.height}','format: RGBA8888','filter: Linear,Linear','repeat: none',name,entry])
        index=next(j for j,s in enumerate(rig['slots']) if s['name']==original_name)+1
        slot=copy.deepcopy(rig['slots'][index-1]);slot.update(name=name,attachment=name,color='ffffff00');rig['slots'].insert(index,slot)
        for skin in skins:
            a=copy.deepcopy(skin['attachments'][original_name][original_name]);a['path']=name;skin['attachments'][name]={name:a}
        awaken[name]={'alpha':[{'value':0.},{'time':1.,'value':1.}]}
        rig['animations']['body_visibility']['slots'][name]={'alpha':[{'value':0.},{'time':1.,'value':0.}]}
    rig['animations']['side_eye_light']={'slots':awaken}
    # 黑白两次采样相减，保留头骨对眼球的遮挡，不烘焙被盖住的眼球轮廓。
    rig['animations']['eye_stencil']={'slots':{f'eye_core_{i}':{'alpha':[{'value':1.}], 'rgb':[{'color':'000000'},{'time':1.,'color':'ffffff'}]} for i in range(3)}}
    # 攻击沿用原有骨白偏金，死亡单独选用纯白轨道。
    for timeline in rig['animations']['eye_light']['slots'].values():timeline['rgb']=[{'color':'fff4cd'}]
    rig['animations']['white_eye_light']=copy.deepcopy(rig['animations']['eye_light'])
    for timeline in rig['animations']['white_eye_light']['slots'].values():timeline['rgb']=[{'color':'ffffff'}]
    encoded=json.dumps(rig,ensure_ascii=False,separators=(',',':'))
    for key in ids:
        folder=root/key
        for n,data in raw.items():(folder/n).write_bytes(data)
        (folder/'boss.atlas').write_text('\n'.join(atlas)+'\n',encoding='utf-8')
        (folder/'boss.spine-json').write_text(encoded,encoding='utf-8')
        config=json.loads((folder/'animation.json').read_text(encoding='utf-8'));config['seal_slots']=seal_names
        config['texture_pages']=list(raw);config['phase_break']=3.
        (folder/'animation.json').write_text(json.dumps(config,ensure_ascii=False,indent=2),encoding='utf-8')
    print('羊头共享骨架：双皮肤、真眼 deform、',len(seal_names),'片额眼表层')

def fracture(root):
    """从交接姿势生成 Voronoi 分块；裂纹与光束锚点使用同一组边。"""
    import cv2
    folder=root/'goat_eye'
    im=Image.open(folder/'death_pose.png').convert('RGBA');size=1024
    # R 保存精确眼形，G 保存柔晕；二者与主体共用 UV 和裂解顶点。
    light=np.array(Image.open(folder/'death_eyes_white.png').convert('RGBA'),dtype=np.int16)
    dark=np.array(Image.open(folder/'death_eyes_black.png').convert('RGBA'),dtype=np.int16)
    eye=Image.fromarray(np.clip(light[:,:,0]-dark[:,:,0],0,255).astype(np.uint8))
    visible_eye=Image.new('RGBA',eye.size,'white');visible_eye.putalpha(eye);visible_eye.save(folder/'death_eyes.png')
    eye_map=Image.merge('RGBA',(eye,eye.filter(ImageFilter.GaussianBlur(6)),Image.new('L',eye.size,0),Image.new('L',eye.size,255)))
    # 分布覆盖巨角、面骨及飘带，避免规则方格；结构块不受碎屑数量倍率影响。
    seeds=[(338,300),(390,255),(440,288),(510,295),(580,277),(645,310),(675,360),
           (340,370),(390,357),(462,350),(526,343),(586,365),(650,435),
           (357,450),(420,428),(485,408),(552,420),(609,477),
           (408,507),(483,493),(542,495),(490,558),(540,557),
           (425,591),(570,590),(394,635),(453,663),(551,657),(595,646),
           (320,550),(700,535),(350,210),(640,218),(500,215)]
    subdiv=cv2.Subdiv2D((0,0,size,size))
    for point in seeds:subdiv.insert(point)
    facets,centers=subdiv.getVoronoiFacetList([])
    mesh=[];cracks=Image.new('RGBA',(size,size),(0,0,0,0));draw=ImageDraw.Draw(cracks)
    rays=[]
    alpha=np.array(im)[:,:,3]
    for i,(polygon,center) in enumerate(zip(facets,centers)):
        poly=np.clip(polygon,0,size-1)
        mesh.append({'center':[float(x) for x in center],'points':poly.tolist(),'seed':i/len(seeds)})
        for a,b in zip(poly,np.roll(poly,-1,axis=0)):
            mid=(a+b)*.5;x,y=map(int,mid)
            if y<535 and alpha[y,x]>180 and np.linalg.norm(a-b)>20:
                dist=np.linalg.norm(mid-np.array([510,345]))
                order=float(np.clip(dist/320,0,1));color=(round(order*255),255,255,255)
                draw.line([tuple(a),tuple(b)],fill=color,width=3)
                rays.append({'point':mid.tolist(),'center':center.tolist(),'seed':i/len(seeds),'distance':dist})
    # 按角度分散九束，起点必须落在真正有颜色的裂缝上。
    picked=[]
    for angle in np.linspace(-math.pi,math.pi,9,endpoint=False):
        candidates=[r for r in rays if all(np.linalg.norm(np.array(r['point'])-q['point'])>24 for q in picked)]
        if not candidates:break
        best=min(candidates,key=lambda r:abs(math.atan2(math.sin(math.atan2(r['point'][1]-405,r['point'][0]-512)-angle),math.cos(math.atan2(r['point'][1]-405,r['point'][0]-512)-angle))))
        picked.append(best)
    payload={'pieces':mesh,'rays':picked}
    # 裂纹只出现于原贴图透明轮廓内。
    a=np.array(cracks);a[:,:,3]=(a[:,:,3].astype(float)*alpha/255).astype(np.uint8)
    for key in ['goat','goat_eye']:
        eye_map.save(root/key/'death_eye_map.png')
        (root/key/'fracture.json').write_text(json.dumps(payload,separators=(',',':')),encoding='utf-8')
        Image.fromarray(a).save(root/key/'cracks.png')
        if key!='goat_eye':shutil.copy2(folder/'death_pose.png',root/key/'death_pose.png')
    print('裂解结构：',len(mesh),'块，',len(picked),'条裂缝光束')

if __name__=='__main__':
    fracture(Path(__file__).resolve().parents[2]/'assets/bosses/animation_studies')
