"""同步正式 UI 与审看共用的三个火框表现参数。"""
import json
from pathlib import Path
root=Path(__file__).resolve().parents[2];path=root/'content/rules/planning_parameters.json'
rows=[r for r in json.loads(path.read_text(encoding='utf-8')) if r['target']!='ui_flame']
for key,name,value,unit,lo,hi,step,meaning in [
    ('flame_height','火势高度',48.,'设计 px',24,72,2,'控制火舌的基准高度；根部固定，焰身持续上窜，少数火簇较大、其余细短。调节时环带透明边距同步更新，不拉伸整张原图。'),
    ('speed','燃烧速度',90.,'设计 px/s',0,180,5,'控制焰身上窜、卷动与尖端消退的时间速度；0冻结，红蓝共用同一运动规律。'),
    ('glow_strength','柔晕强度',1.,'倍',0,2,.1,'只调节局部外晕及八个附属火尖；0保留主要火焰，不改变文字或背景亮度。')]:
    rows.append(dict(section='10 UI 火框',target='ui_flame',key=key,name=name,default=value,unit=unit,suggested=f'{lo}～{hi}',step=step,minimum=lo,maximum=hi,meaning=meaning,type='float',source='src/presentation/ui/flame_frame_visual.gd'))
path.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
