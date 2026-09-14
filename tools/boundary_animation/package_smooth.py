"""60 fps 原生采样与比例对照；保留上一轮交付，便于回看。"""
from pathlib import Path
import argparse
import os
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

OUT=Path(__file__).resolve().parents[2]/'build/boundary-animation'
FONT=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--before',default='smooth-before')
    parser.add_argument('--after',default='smooth-after')
    parser.add_argument('--name',default='waves-smooth')
    args=parser.parse_args()
    # Windows 下 OpenCV 的窄字符路径不能可靠打开中文目录，编码器使用相对路径。
    os.chdir(OUT)
    frames=sorted((OUT/args.after).glob('*.png'))
    assert len(frames)==240, '需要 4 秒、60 fps 的连续渲染采样'
    video_name=args.name+'-60fps.webm';comparison_name=args.name+'-comparison-60fps.webm'
    video=cv2.VideoWriter(video_name,cv2.VideoWriter_fourcc(*'VP80'),60,(1920,1080))
    comparison=cv2.VideoWriter(comparison_name,cv2.VideoWriter_fourcc(*'VP80'),60,(1440,800))
    assert video.isOpened() and comparison.isOpened()
    for path in frames:
        video.write(cv2.imread(str(path.relative_to(OUT))))
        pair=Image.new('RGB',(1440,800),(48,45,61));draw=ImageDraw.Draw(pair)
        for n,folder in enumerate([args.before,args.after]):
            # 全宽局部保持等比，中央与两侧小浪在同一时间并排审看。
            source=Image.open(OUT/folder/path.name).convert('RGB')
            pair.paste(source.crop((0,300,1920,780)).resize((1440,360),Image.Resampling.LANCZOS),(0,n*400+40))
            draw.text((16,n*400+7),['调整前','调整后'][n],font=FONT,fill='white')
        comparison.write(cv2.cvtColor(np.array(pair),cv2.COLOR_RGB2BGR))
    video.release();comparison.release()
    for name in [video_name,comparison_name]:
        decoded=cv2.VideoCapture(name)
        assert decoded.get(cv2.CAP_PROP_FRAME_COUNT)==240 and decoded.get(cv2.CAP_PROP_FPS)==60
        assert decoded.read()[0], '视频必须可解码'
        decoded.release()
    sheet=Image.new('RGB',(1440,1200),(48,45,61));draw=ImageDraw.Draw(sheet)
    for n,i in enumerate([0,24,48,72,90,102,114,138]):
        source=Image.open(frames[i]).convert('RGB').crop((180,315,1080,665)).resize((720,280),Image.Resampling.LANCZOS)
        x=n%2*720;y=n//2*300;sheet.paste(source,(x,y+20));draw.text((x+8,y),f'{i/60:.2f} s',font=FONT,fill='white')
    sheet.save(OUT/(args.name+'-phases.png'))
    print('PACKAGED: 4 sec / 240 frames / 60 fps, native and comparison')

if __name__=='__main__':main()
