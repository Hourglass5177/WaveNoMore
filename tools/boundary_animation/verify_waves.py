"""离线检查可编辑附件、透明画布、加权网格翻折与水带连接。"""
from pathlib import Path
import json,math
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
folder=ROOT/'assets/image/background/boundary_waves'
doc=json.loads((folder/'wave.spine-json').read_text())
meshes=doc['skins'][0]['attachments']['water']
for name in meshes:
    im=Image.open(folder/'parts'/(name+'.png'))
    assert im.mode=='RGBA' and im.size==(384,256),name
    alpha=np.array(im)[:,:,3]
    assert not alpha[:3].any() and not alpha[-3:].any(),name+' vertical padding'
mesh=next(iter(meshes.values()));data=mesh['vertices'];points=[];i=0
while i<len(data):
    count=data[i];i+=1;point=[]
    for _ in range(count):point.append(data[i:i+4]);i+=4
    assert abs(sum(v[3] for v in point)-1)<1e-5
    points.append(point)
def sample(keys,t,key):
    return float(np.interp(t,[p['time'] for p in keys],[p.get(key,0) for p in keys]))
timeline=doc['animations']['break']['bones'];minimum=1e9
for t in np.linspace(0,1,257):
    transformed=[]
    for influences in points:
        px=py=0
        for bone,x,y,w in influences:
            name=doc['bones'][bone]['name'];track=timeline.get(name,{})
            r=math.radians(sample(track.get('rotate',[{'time':0}]),t,'value'))
            tx=doc['bones'][bone].get('x',0)+sample(track.get('translate',[{'time':0}]),t,'x')
            ty=doc['bones'][bone].get('y',0)+sample(track.get('translate',[{'time':0}]),t,'y')
            px+=(x*math.cos(r)-y*math.sin(r)+tx)*w
            py+=(x*math.sin(r)+y*math.cos(r)+ty)*w
        transformed.append((px,py))
    coords=np.array(transformed)
    for a,b,c in np.array(mesh['triangles']).reshape(-1,3):
        u,v=coords[b]-coords[a],coords[c]-coords[a]
        area=(u[0]*v[1]-u[1]*v[0])/2
        assert area>0,(t,a,b,c,area)
        minimum=min(minimum,area)
band=np.array(Image.open(folder/'water_band.png'))
assert np.all(band[720,66:2586,3]>0),'waterline seam'
source=np.array(Image.open(ROOT/'assets/image/background/edge.png'))
# 水带内部的原画块面必须原样保留，不能再被水平裁切或整体拉伸。
inside=source[690:730,:,3]==255
assert np.array_equal(band[690:730][inside],source[690:730][inside]),'original band interior'
for x in [100,800,1600,1900,2300]:
    visible=source[:,x,3]>0
    assert np.array_equal(band[visible,x],source[visible,x]),'original relief at '+str(x)
control=np.array(Image.open(folder/'flow_control.png')).astype(int)
assert control.shape==(720,1325,4)
assert abs(control[:,:,:2]+control[::-1,::-1,:2]-255).max()<=1,'flow vector symmetry'
assert np.array_equal(control[:,:,2:],control[::-1,::-1,2:]),'flow mask and phase symmetry'
assert Image.open(folder/'flow_streaks.png').size==(512,96)
report={'attachments':len(meshes),'sampled_poses':257,'minimum_triangle_area':minimum,'waterline_connected':True}
(ROOT/'build/boundary-animation/geometry-v2.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report))
