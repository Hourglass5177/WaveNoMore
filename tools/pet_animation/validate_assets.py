"""检查派生网格及实际渲染 PNG：翻面、裁切、消逝边界和原画保留。"""
from pathlib import Path
import json
import math
import numpy as np
from PIL import Image

GAME = Path(__file__).resolve().parents[2]
ASSETS = GAME/'assets/pets/animation_studies'
RENDER = GAME/'build/pet-animation'


def matrices(data, clip, frame):
    result=[]
    lookup={bone['name']:i for i,bone in enumerate(data['bones'])}
    tracks=data['animations'][clip]['bones']
    for bone in data['bones']:
        keys=tracks[bone['name']]
        def value(kind): return keys[kind][min(frame,len(keys[kind])-1)]
        angle=math.radians(value('rotate')['value'])
        s=value('scale'); t=value('translate')
        c=math.cos(angle); sn=math.sin(angle)
        local=np.array([[c*s['x'],-sn*s['y'],bone.get('x',0)+t['x']],
                        [sn*s['x'],c*s['y'],bone.get('y',0)+t['y']],
                        [0,0,1]])
        result.append(result[lookup[bone['parent']]]@local if 'parent' in bone else local)
    return result


def mesh_points(attachment, transforms):
    source=attachment['vertices']; cursor=0; points=[]
    while cursor<len(source):
        count=source[cursor]; cursor+=1; point=np.zeros(3)
        for _ in range(count):
            bone,x,y,weight=source[cursor:cursor+4]; cursor+=4
            point += (transforms[bone]@np.array([x,y,1]))*weight
        points.append(point[:2])
    return np.array(points)


def area(points, triangles):
    p=points[np.array(triangles).reshape(-1,3)]
    a=p[:,1]-p[:,0];b=p[:,2]-p[:,0]
    return a[:,0]*b[:,1]-a[:,1]*b[:,0]


def main():
    frame_count=0; mesh_samples=0; narrowest=512; min_area_ratio=1.0
    for key in ['bat','snake','sheep']:
        folder=ASSETS/key
        meta=json.loads((folder/'animation.json').read_text(encoding='utf-8'))
        data=json.loads((folder/'pet.spine-json').read_text(encoding='utf-8'))
        original=GAME.parent/'Assets/随从宠物原画'/(meta['name']+'.png')
        assert (folder/'original.png').read_bytes()==original.read_bytes(),key+' 原画被改写'
        attachments=[next(iter(slot.values())) for slot in data['skins'][0]['attachments'].values()]
        initial=matrices(data,'idle',0)
        areas=[area(mesh_points(part,initial),part['triangles']) for part in attachments]
        for clip in ['idle','trigger','death']:
            poses=len(data['animations'][clip]['bones']['root']['rotate'])
            for frame in range(poses):
                transforms=matrices(data,clip,frame)
                for part,rest in zip(attachments,areas):
                    deformed=mesh_points(part,transforms)
                    ratio=area(deformed,part['triangles'])/rest
                    assert np.isfinite(deformed).all() and ratio.min()>.02,(key,clip,frame,'网格翻折')
                    min_area_ratio=min(min_area_ratio,float(ratio.min()))
                    mesh_samples+=1
            images=sorted((RENDER/key/clip).glob('*.png'))
            expected=math.ceil(meta[clip]*30)+(clip=='death')
            assert len(images)==expected,(key,clip,'导出帧数')
            for index,path in enumerate(images):
                im=Image.open(path).convert('RGBA'); box=im.getbbox()
                assert im.size==(512,512),(key,clip,'画布尺寸')
                if box:
                    margin=min(box[0],box[1],512-box[2],512-box[3])
                    narrowest=min(narrowest,margin)
                    assert margin>=8,(key,clip,index,'画布裁切')
                if clip=='death' and index==len(images)-1:
                    assert box is None,key+' 死亡结束仍有像素'
                frame_count+=1
        # 1.4 秒只交接灰烬，不应跳位置或重复叠一层本体。
        before=np.asarray(Image.open(RENDER/key/'death/0041.png')).astype(int)
        ash=np.asarray(Image.open(RENDER/key/'death/0042.png')).astype(int)
        alpha_error=np.abs(before[:,:,3]-ash[:,:,3]).mean()
        assert alpha_error<.5,(key,'灰烬交接轮廓不连续',alpha_error)
        print(key, 'mesh/frames/ashes OK, handoff alpha MAE',round(alpha_error,4))
    print(f'{frame_count} rendered frames, {mesh_samples} mesh samples; '
          f'minimum canvas margin {narrowest}px; minimum triangle area ratio {min_area_ratio:.3f}')


if __name__=='__main__': main()
