"""按 edge.png 的原图坐标生成连续形变权重；不改写原画和透明轮廓。"""
from pathlib import Path
import numpy as np
from PIL import Image

GAME = Path(__file__).resolve().parents[2]
SOURCE = GAME/'assets/image/background/edge.png'
OUT = GAME/'assets/image/background/boundary_motion'


def weights(width=1325, height=720):
    # 控制图半分辨率足以描述宽缓形变；对称的是位移场，原画细节不做镜像替换。
    y,x=np.mgrid[:height,:width].astype(float)
    x=(x+.5)*2650/width; y=(y+.5)*1440/height
    def pair(cx,cy,rx,ry):
        one=np.exp(-(((x-cx)/rx)**2+((y-cy)/ry)**2)*2)
        two=np.exp(-(((x-(2650-cx))/rx)**2+((y-(1440-cy))/ry)**2)*2)
        return np.maximum(one,two)
    small=np.maximum.reduce([pair(370,630,130,105),pair(710,620,150,115),pair(970,675,110,80)])
    crest_tip=pair(1330,565,120,110)
    curl=np.maximum(pair(1245,638,220,170),crest_tip)
    tips=np.maximum(small,crest_tip)
    return np.stack([small,curl,tips,np.ones_like(x)],axis=-1)


if __name__=='__main__':
    assert Image.open(SOURCE).size==(2650,1440)
    OUT.mkdir(parents=True,exist_ok=True)
    control=weights()
    assert np.max(np.abs(control-control[::-1,::-1]))<1e-10
    Image.fromarray(np.round(control*255).astype('uint8')).save(OUT/'controls.png')
    print('Generated boundary controls: 1325 x 720, centrally symmetric weights')
