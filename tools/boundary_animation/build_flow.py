"""从现有水带生成流向、边缘固定权重及原画细水线；不重画原素材。"""
from pathlib import Path
import numpy as np
import cv2
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/image/background/boundary_waves'
SCALE=.7616555803103707

def build_flow():
    band=np.array(Image.open(OUT/'water_band.png').convert('RGBA'))
    h,w=band.shape[:2];mask=band[:,:,3]>32
    # 中轴取原画厚水带的重心，平滑掉局部碎边，再配成中心对称的流向。
    weights=mask.sum(0);center=(mask*np.arange(h)[:,None]).sum(0)/np.maximum(weights,1)
    valid=np.flatnonzero(weights);center=np.interp(np.arange(w),valid,center[valid])
    center=cv2.GaussianBlur(center.reshape(1,-1),(0,0),24).ravel()
    center=(center+h-center[::-1])/2
    slope=np.gradient(center)
    yy,xx=np.mgrid[:h,:w].astype('float32');dx=xx+.5-w/2;dy=yy+.5-h/2
    direction=np.where(dx<0,1.,-1.)
    thickness=(weights+weights[::-1])/2
    speed=np.clip(72/np.maximum(thickness,1),.65,1.)
    vx=direction*speed[None,:]
    vy=vx*slope[None,:]+.22*(dx/180)*np.exp(-(dx/230)**2)
    distance=cv2.distanceTransform(mask.astype('uint8'),cv2.DIST_L2,cv2.DIST_MASK_PRECISE)*SCALE
    # 6 px 的薄边完全固定；再用 5 px 过渡到可流动内部。
    pin=np.clip((distance-6)/5,0,1);pin=pin*pin*(3-2*pin)
    radius=np.sqrt(dx*dx+dy*dy)*SCALE
    central=np.clip((radius-55)/90,0,1);central=central*central*(3-2*central)
    pin*=central
    pin=np.minimum(pin,pin[::-1,::-1])
    # 相位也是中心对称的平滑场，避免整条水面同时重置。
    phase=.5+.23*np.sin(abs(dx)/113+np.cos(dy*direction/31))+.16*np.sin(abs(dx)/47+dy*direction/23)
    control=np.dstack([np.clip(vx,-1,1)*.5+.5,np.clip(vy,-1,1)*.5+.5,pin,np.clip(phase,.06,.94)])
    control=cv2.resize(control,(w//2,h//2),interpolation=cv2.INTER_AREA)
    Image.fromarray(np.rint(control*255).astype('uint8')).save(OUT/'flow_control.png')

    # 提取原画薄白水线的明度断续，统一为可重复的 512×96 设计像素贴片。
    original=np.array(Image.open(ROOT/'assets/image/background/edge.png').convert('RGBA'))/255
    strip=np.zeros((96,512,4),dtype='float32')
    for i,(x,y,length,width) in enumerate([(13,12,86,2),(139,28,43,2),(238,9,67,3),(370,39,98,2),
                                          (61,64,54,3),(187,82,97,2),(334,70,38,2),(439,90,55,2)]):
        src=original[698+(i%3)*10:708+(i%3)*10,85+i*105:245+i*105]
        bright=np.clip((src[:,:,:3].mean(2)-.62)/.25,0,1)*src[:,:,3]
        pattern=cv2.resize(bright,(length,width),interpolation=cv2.INTER_AREA)
        end=np.sin(np.linspace(0,np.pi,length))**.6
        strip[y:y+width,x:x+length,:3]=np.array([.92,.88,.81]) if i%2==0 else np.array([.70,.66,.80])
        strip[y:y+width,x:x+length,3]=pattern*end
    Image.fromarray(np.rint(strip*255).astype('uint8')).save(OUT/'flow_streaks.png')
    print('FLOW: 1325x720 RG vectors / B interior / A phase; 512x96 original-art streaks')

if __name__=='__main__':build_flow()
