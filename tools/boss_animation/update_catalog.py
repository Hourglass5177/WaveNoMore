"""只同步 BOSS 审看的三个表现倍率，不重新生成其他策划字段。"""
import json
from pathlib import Path
root=Path(__file__).resolve().parents[2]
path=root/'content/rules/planning_parameters.json'
rows=json.loads(path.read_text(encoding='utf-8'))
rows=[r for r in rows if r['target']!='boss']
for key,name,low,high,step,meaning in [
    ('glow_strength','光效强度',0,2,.1,'调整光波、火焰、眼光及羊头裂光和白场。攻击不提亮手部，默认白场保持0.5秒。'),
    ('effect_scale','光效范围',.5,1.5,.1,'调整光波、火焰及羊头光束和骨片扩散范围，发射根部保持绑定。'),
    ('fragment_multiplier','碎片数量倍率',.25,2,.25,'调整附属碎屑数量。羊头六片额眼表层与34块骨片固定，不改变动作时长。'),
]:
    rows.append(dict(section='09 BOSS 表现',target='boss',key=key,name=name,default=1.0,unit='倍',suggested=f'{low}～{high}',step=step,minimum=low,maximum=high,meaning=meaning,type='float',source='tools/boss_animation/boss_visual.gd'))
path.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
