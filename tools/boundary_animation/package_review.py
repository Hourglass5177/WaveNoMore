"""仅整理 Compatibility 原生采样，输出同场对照、近景和实机动图。"""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2]/'build/boundary-animation'
FONT=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',22)

def save_gif(frames,path):
    # 共用调色板，避免柔和的粉灰块面逐帧跳色。
    palette=frames[len(frames)//2].quantize(colors=256)
    frames=[im.quantize(palette=palette,dither=Image.Dither.NONE) for im in frames]
    frames[0].save(path,save_all=True,append_images=frames[1:],duration=[33,33,34]*(len(frames)//3),loop=0,optimize=False,disposal=2)

def run():
    modes=['static','flow','beat']
    samples={mode:sorted((ROOT/mode).glob('*.png')) for mode in modes}
    if samples['static'] and all(len(samples[mode])==180 for mode in ['flow','beat']):
        comparisons=[]; full=[]; close=[]
        for i in range(180):
            frame=Image.open(samples['beat'][i]).convert('RGB')
            full.append(frame.resize((1280,720),Image.Resampling.LANCZOS))
            close.append(frame.crop((755,360,1165,730)).resize((820,740),Image.Resampling.LANCZOS))
            board=Image.new('RGB',(1350,396),'#252130'); draw=ImageDraw.Draw(board)
            for j,(mode,label) in enumerate(zip(modes,['静态','仅缓流','缓流＋节拍回应'])):
                view=Image.open(samples[mode][0 if mode=='static' else i]).convert('RGB').crop((715,350,1205,740)).resize((450,358),Image.Resampling.LANCZOS)
                board.paste(view,(j*450,38)); draw.text((j*450+16,7),label,font=FONT,fill='#eee8da')
            comparisons.append(board)
        save_gif(full,ROOT/'boundary-full.gif'); save_gif(close,ROOT/'boundary-close.gif'); save_gif(comparisons,ROOT/'boundary-comparison.gif')
        comparisons[108].save(ROOT/'comparison.png')
    game=sorted((ROOT/'game').glob('*.png'))
    if len(game)==180:
        save_gif([Image.open(p).convert('RGB').resize((1280,720),Image.Resampling.LANCZOS) for p in game],ROOT/'boundary-gameplay.gif')
    print('Packaged native boundary review')

if __name__=='__main__':run()
