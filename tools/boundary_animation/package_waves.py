"""将实际渲染采样打包为四小节样片、中央近景及关键时刻；不改动画素材。"""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/boundary-animation'
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',18)

def gif(frames,path):
    # 共用调色板避免固定背景随帧闪色；只编码帧间变化区域。
    palette=frames[0].convert('RGB').quantize(colors=192)
    indexed=[f.convert('RGB').quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
    indexed[0].save(path,save_all=True,append_images=indexed[1:],duration=([30,30,40]*((len(frames)+2)//3))[:len(frames)],loop=0,disposal=1,optimize=False)

def runtime():
    new=[OUT/'new'/f'{i:04}.png' for i in range(240)]
    old=[OUT/'legacy'/f'{i:04}.png' for i in range(240)]
    assert all(p.exists() for p in new+old),'正式同场截帧尚未完成'
    comparison=[];full=[]
    for a,b in zip(old,new):
        left=Image.open(a).convert('RGB');right=Image.open(b).convert('RGB')
        full.append(right.resize((1280,720),Image.Resampling.LANCZOS))
        pair=Image.new('RGB',(1280,780),(48,45,61));d=ImageDraw.Draw(pair)
        pair.paste(left.crop((640,320,1280,700)),(0,20));pair.paste(right.crop((640,320,1280,700)),(640,20))
        pair.paste(left.resize((640,360)),(0,420));pair.paste(right.resize((640,360)),(640,420))
        d.text((12,0),'旧版',font=font,fill='white');d.text((652,0),'新版',font=font,fill='white')
        comparison.append(pair)
    gif(full,OUT/'waves-stage-full.gif');gif(comparison,OUT/'waves-comparison.gif')
    paths=[OUT/'game'/f'{i:04}.png' for i in range(120)]
    assert all(p.exists() for p in paths),'关内采样尚未完成'
    gif([Image.open(p).convert('RGB').resize((1280,720),Image.Resampling.LANCZOS) for p in paths],OUT/'waves-gameplay.gif')
    print('PACKAGED formal 4-bar comparison and 4-second gameplay')

def video():
    # WebM 保留完整画面颜色；GIF 的 256 色仅用于快速动图审看。
    import cv2
    writer=cv2.VideoWriter(str(OUT/'waves-stage-native.webm'),cv2.VideoWriter_fourcc(*'VP80'),30,(1920,1080))
    assert writer.isOpened(),'当前 OpenCV 未提供 VP8 编码器'
    for i in range(240):writer.write(cv2.imread(str(OUT/'new'/f'{i:04}.png')))
    writer.release()

def main():
    paths=[OUT/'v2'/f'{i:04}.png' for i in range(240)]
    assert all(p.exists() for p in paths),'四小节截帧尚未完成'
    full=[];close=[]
    for p in paths:
        im=Image.open(p).convert('RGB')
        full.append(im.resize((1280,720),Image.Resampling.LANCZOS))
        close.append(im.crop((650,310,1270,770)))
    gif(full,OUT/'waves-full.gif');gif(close,OUT/'waves-close.gif')
    sheet=Image.new('RGB',(1240,4*490),(48,45,61));draw=ImageDraw.Draw(sheet)
    # 前进、卷顶、翻落、强拍、水沫、接替一并展示，避免只审看单帧。
    for n,i in enumerate([0,15,30,42,51,57,60,75]):
        crop=Image.open(paths[i]).convert('RGB').crop((650,310,1270,770))
        x=(n%2)*620;y=(n//2)*490;sheet.paste(crop,(x,y+30));draw.text((x+12,y+4),f'{i/30:.2f} s · {i/15:.1f} 拍',font=font,fill='white')
    sheet.save(OUT/'waves-phases.png')
    keys=Image.new('RGBA',(4*384,2*286),(48,45,61,255));d=ImageDraw.Draw(keys)
    for i,title in enumerate(['低水脊','陡坡','伸顶','内卷','前翻','触水','摊开','消退']):
        x=(i%4)*384;y=(i//4)*286
        keys.alpha_composite(Image.open(ROOT/'assets/image/background/boundary_waves/keyposes'/f'{i:02}.png'),(x,y+30));d.text((x+12,y+4),title,font=font,fill='white')
    keys.convert('RGB').save(OUT/'waves-keyposes.png')
    print('PACKAGED 240 native frames / 8 sec / 4 bars')

if __name__=='__main__':
    import sys
    if '--video' in sys.argv:video()
    elif '--runtime' in sys.argv:runtime()
    else:main()
