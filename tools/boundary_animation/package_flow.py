"""将三状态真实渲染采样编码为 60 fps 全景、近景与对照。"""
from pathlib import Path
import os
import cv2
import numpy as np
from PIL import Image,ImageDraw,ImageFont
OUT=Path(__file__).resolve().parents[2]/'build/boundary-animation'

def main():
    os.chdir(OUT)
    frames=sorted(Path('flow/full').glob('*.png'));assert len(frames)==360
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',22)
    specifications=[('water-flow-full-60fps.webm',(1920,1080)),('water-flow-close-60fps.webm',(1480,360)),
                    ('water-flow-comparison-60fps.webm',(1280,1056))]
    writers=[cv2.VideoWriter(name,cv2.VideoWriter_fourcc(*'VP80'),60,size) for name,size in specifications]
    assert all(w.isOpened() for w in writers)
    for path in frames:
        full=cv2.imread(str(path));writers[0].write(full)
        writers[1].write(cv2.resize(full[435:615,160:900],(1480,360),interpolation=cv2.INTER_CUBIC))
        sheet=Image.new('RGB',(1280,1056),(48,45,61));draw=ImageDraw.Draw(sheet)
        for i,(mode,label) in enumerate([('still','基底静止'),('color','原纹流动'),('full','原纹与细水纹')]):
            im=Image.open(Path('flow')/mode/path.name).convert('RGB')
            if mode=='full':im=im.crop((0,300,1920,780))
            sheet.paste(im.resize((1280,320),Image.Resampling.LANCZOS),(0,i*352+32))
            draw.text((14,i*352+4),label,font=font,fill='white')
        writers[2].write(cv2.cvtColor(np.array(sheet),cv2.COLOR_RGB2BGR))
        if path.stem=='0060':sheet.save('water-flow-comparison.png')
        if int(path.stem)%120==0:print('ENCODE',path.stem,flush=True)
    for writer in writers:writer.release()
    for name,size in specifications:
        capture=cv2.VideoCapture(name)
        assert capture.get(cv2.CAP_PROP_FPS)==60 and capture.get(cv2.CAP_PROP_FRAME_COUNT)==360
        capture.set(cv2.CAP_PROP_POS_FRAMES,180);ok,image=capture.read();assert ok
        assert (image.shape[1],image.shape[0])==size
        capture.release()
    print('FLOW VIDEOS VERIFIED: 6 seconds / 360 frames / 60 fps')

if __name__=='__main__':main()
