"""对实际控制图采样，检查位移场是否翻折、越过内缘或破坏中心对称。"""
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
CONTROL=np.asarray(Image.open(ROOT/'assets/image/background/boundary_motion/controls.png'),dtype=float)/255

def ramp(a,b,x):
    x=np.clip((x-a)/(b-a),0,1)
    return x*x*x*(x*(x*6-15)+10)

def field(x,y,t,scale=.76165558,stream_amp=3,curl_amp=12,beat_amp=1.2,bpm=120):
    # 与 GPU 的线性过滤相同；读取的是实际导出的 8 位控制图。
    u=np.clip(x/2-.5,0,CONTROL.shape[1]-1.001); v=np.clip(y/2-.5,0,CONTROL.shape[0]-1.001)
    i=u.astype(int); j=v.astype(int); fx=(u-i)[...,None]; fy=(v-j)[...,None]
    c=(CONTROL[j,i]*(1-fx)+CONTROL[j,i+1]*fx)*(1-fy)+(CONTROL[j+1,i]*(1-fx)+CONTROL[j+1,i+1]*fx)*fy
    r,g,b=c[...,0],c[...,1],c[...,2]
    x=x-1325; y=y-720; length=np.sqrt(x*x+y*y)
    pin=ramp(6,30,abs(y))*ramp(108,175,length)
    side=x/np.sqrt(x*x+80**2); travel=(1-np.clip(abs(x)/1325,0,1))*1.5
    time=t%6-b*.2; stream=np.sin(2*np.pi*(time-travel)/6)*stream_amp*(1+r*.65)*(1-g*.72)
    phase=time%6
    lift=ramp(0,2.2,phase)*(1-ramp(3.6,6,phase)); roll=ramp(2.2,3.6,phase)*(1-ramp(3.6,6,phase))
    rx=x/np.maximum(length,1); ry=y/np.maximum(length,1)
    curl_root=ramp(24,130,abs(y))
    dx=-side*.22*stream+(rx*lift*.48-ry*roll*.88)*curl_amp*g*curl_root
    dy=side*stream+(ry*lift*.48+rx*roll*.88)*curl_amp*g*curl_root
    beat=(t*bpm/60)%1; pulse=ramp(0,.18,beat)*(1-ramp(.18,.8,beat))*beat_amp*(1+b*.5)
    dx+=rx*g*pulse; dy+=(side*(1-g)+ry*g)*pulse
    return np.stack([dx,dy],axis=-1)*pin[...,None]/max(scale,.76165558)

def run():
    y,x=np.mgrid[500:940:5,30:2620:8].astype(float)
    jac_min=1; stretch_min=1; stretch_max=1; tip=[]; sym=0
    for t in np.linspace(0,6,241):
        delta=field(x,y,t)
        a=(field(x+1,y,t)-field(x-1,y,t))*.5
        b=(field(x,y+1,t)-field(x,y-1,t))*.5
        jac=(1+a[...,0])*(1+b[...,1])-a[...,1]*b[...,0]
        jac_min=min(jac_min,float(jac.min()))
        jacobian=np.stack([a,b],axis=-1)+np.eye(2)
        singular=np.linalg.svd(jacobian,compute_uv=False)
        stretch_min=min(stretch_min,float(singular.min())); stretch_max=max(stretch_max,float(singular.max()))
        sym=max(sym,float(abs(delta+field(2650-x,1440-y,t)).max()))
        tip.append(field(np.array(1330.),np.array(565.),t)*.76165558)
    result={'minimum_jacobian':jac_min,'local_stretch_range':[stretch_min,stretch_max],
            'symmetry_error_source_px':sym,'outer_tip_travel_design_px':float(np.ptp(np.array(tip)[:,0])),
            'samples':241,'grid_points_per_sample':int(x.size)}
    assert jac_min>0.0, result
    assert sym<1e-8,result
    assert result['outer_tip_travel_design_px']>=8,result
    target=ROOT/'build/boundary-animation/geometry.json'; target.write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result,indent=2))

if __name__=='__main__':run()
