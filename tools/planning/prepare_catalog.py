"""从当前原型整理策划字段。目录元数据同时用于表格、文档和读取检查。"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
rows = []
rules_source = 'src/content/resources/gameplay_rule_set.gd'
script = (ROOT / rules_source).read_text(encoding='utf-8')
preset = (ROOT / 'content/rules/default_gameplay_rules.tres').read_text(encoding='utf-8')

def rule(section, key, name, unit, suggested, step, meaning, low, high):
    literal = re.search(r'var ' + key + r': \w+ = ([^\n]+)', script)[1].strip()
    override = re.search(r'^' + key + r' = ([^\n]+)', preset, re.M)
    value = json.loads(override[1] if override else literal)
    rows.append(dict(section=section, target='rules', key=key, name=name, default=value,
                     unit=unit, suggested=suggested, step=step, meaning=meaning,
                     minimum=low, maximum=high, source=rules_source,
                     type='bool' if isinstance(value,bool) else 'int' if isinstance(value,int) else 'float'))

rule('01 判定与容错','perfect_window_ms','Perfect 时间窗','ms','30～60',5,'Tap 与 Hold 头部共享；允许提前或延后同样的时间。越大越宽松。',1,500)
rule('01 判定与容错','good_window_ms','Good 时间窗','ms','60～110',5,'超出 Perfect 后仍可获得 Good 的最大绝对误差。',1,500)
rule('01 判定与容错','pass_window_ms','Pass 时间窗','ms','100～160',5,'主动输入被接受的最外边界；不是 Miss 窗。',1,500)
rule('01 判定与容错','miss_window_ms','无人命中超时','ms','150～220',5,'头部未命中，在判定时间之后超过该值才记 Miss。',1,1000)
rule('01 判定与容错','hold_sustain_grace_ms','Hold 断持宽限','ms','60～150',10,'短暂松开可续接；超时失败并淡出关联调频条。尾点自动完成，无松尾判定。',1,500)
rule('02 魂火与惩罚','max_soul_fire','开局与最大魂火','点','80～150',10,'共享生命池；没有普通命中自动回血。',1,1000)
rule('02 魂火与惩罚','tap_miss_damage','Tap 漏击伤害','点','10～25',1,'抵达角色时扣血；同一 Tap 伤害组只扣一次。',0,1000)
rule('02 魂火与惩罚','hold_segment_damage','Hold 每段身体伤害','点/段','1～4',1,'未消耗身体抵达角色后按拍逐段扣血；无额外头部或整条失败伤害。',0,1000)
rule('02 魂火与惩罚','hold_damage_segment_beats','Hold 伤害单位拍长','拍/段','1/8～1/2',0.0625,'1 拍为四分音符；默认 0.25 拍，变 BPM 改变间隔而不改变总伤害。',0.0625,4)
rule('02 魂火与惩罚','ghost_miss_damage','Ghost 漏击伤害','点/枚','5～15',1,'按关联调频完成情况判定；失败逐枚扣血。预测位置只作引导，不额外判相纹碰撞。',0,1000)
rule('02 魂火与惩罚','stray_input_damage','空按伤害','点/次','5～20',1,'仅开启空按扣魂火时使用，独立于三类音符伤害。',0,1000)
rule('02 魂火与惩罚','stray_input_breaks_combo','空按中断 Combo','开关','通常关闭',1,'开启后没有机制消费的按下会断连；与扣血开关独立。',0,1)
rule('02 魂火与惩罚','stray_input_damages','空按扣魂火','开关','通常关闭',1,'开启后按独立的空按伤害扣血；不会自动打开断连。',0,1)
rule('03 调频','tuning_speed_tolerance_ms','每程完成容错','ms','100～500',25,'摇杆推进速度=弧长/max(该程秒数−容错秒数,0.001)；增大更易提前完成，不延长尾点。',0,2000)
rule('03 调频','tuning_stick_deadzone','摇杆径向死区','比例','15%～25%',0.01,'死区外按 (幅度−死区)/(1−死区) 线性映射速度；越大越抗漂移。',0,0.9)
rule('03 调频','tuning_endpoint_capture_ratio','端点捕获比例','比例','1%～6%',0.005,'端点吸附与视觉捕获区，另用于 Ghost 区间内引导进度的容差；Tuning 终点评分读取完成度阈值。',0.001,0.25)
rule('03 调频','tuning_perfect_completion','Tuning Perfect 完成度','比例','95%～100%',0.01,'每程规定终点时刻最低完成比例；须按住对应钟，允许提前完成。',0,1)
rule('03 调频','tuning_good_completion','Tuning Good 完成度','比例','85%～95%',0.01,'不足 Perfect 时达到此比例记 Good；不增加晚到窗口。',0,1)
rule('03 调频','tuning_pass_completion','Tuning Pass 完成度','比例','70%～85%',0.01,'最低成功比例；低于此值或松开记 Miss。关联 Hold 失败后滑条淡出，仍按原时刻结算；仅 Ghost 扣血。',0,1)
rule('03 调频','tuning_base_frequency_hz','基准载波频率','Hz','2～4',0.25,'普通段及调频段起始基频；影响载波疏密和 Ghost 候选。',0.1,30)
rule('03 调频','tuning_min_frequency_hz','最低载波频率','Hz','0.5～2',0.25,'应低于最高频率，并且不高于基频。',0.1,30)
rule('03 调频','tuning_max_frequency_hz','最高载波频率','Hz','5～9',0.25,'提高会增加波纹密度，并改变角度到频率的映射；需复查整谱。',0.1,30)
rule('03 调频','tuning_pixels_per_hz','每 Hz 的编排尺度','设计 px/Hz','120～200',10,'连接角跨度、频率跨度与鼠标位移；不是单纯改变条身尺寸。',1,1000)
rule('03 调频','tuning_guide_time_window_ms','时间引导余量','ms','150～350',25,'只拓展视觉引导范围，不扩大真实判定窗口。',0,500)
rule('03 调频','tuning_spatial_margin','空间引导余量','比例','8%～16%',0.01,'只拓展视觉引导范围，按完整频率轴长度计算。',0,0.5)
rule('04 计分','perfect_score','Perfect 基础分','分','保持 1000 为基准',100,'按判定单位计分；Hold 整条为一个单位，不按秒连续给分。',0,100000)
rule('04 计分','good_score','Good 基础分','分','Perfect 的 60%～80%',50,'再乘当前 Combo 倍率。',0,100000)
rule('04 计分','pass_score','Pass 基础分','分','Perfect 的 30%～50%',50,'必须大于零；再乘当前 Combo 倍率。',1,100000)
rule('04 计分','miss_score','Miss 基础分','分','通常为 0',1,'Miss 会清零 Combo；不乘 Combo 倍率。',0,100000)
rule('04 计分','max_combo_multiplier','最高 Combo 倍率','倍','1～2',0.1,'从 1 倍线性爬升；高连击影响总分权重。',0,10)
rule('04 计分','combo_steps_to_max','倍率爬升步数','次','50～150',10,'倍率按 (Combo−1)/步数计算；默认第 101 连达到上限。',1,500)
rule('05 读谱与声波','approach_duration_sec','音符接近时间','s','1.5～3',0.1,'生成至判定点的时间；增大能更早看见音符，且改变速度与接触几何。',0.1,10)
rule('05 读谱与声波','ghost_preview_extra_sec','Ghost 额外预告','s','0.2～0.8',0.05,'在普通接近时间前额外显示闭眼 Ghost；同步提前固定预测位置的取样边界，不改变结算时刻、调频评分或伤害。',0,2)
rule('05 读谱与声波','wave_speed_px_sec','声波传播速度','设计 px/s','1800～3000',100,'影响实际接触、载波间距与 Ghost 选点；不改变按键时间窗。',10,4000)

for pet, name, key, values, unit, recommended, step, limits, meaning in [
    ('nu_tu_fu','女土蝠','perfect_score_bonus',[0.02,0.03],'比例','1%～5%',0.005,(0,1),'对含 Combo 的 Perfect 分累计奖励，最后累计取整。'),
    ('gui_jin_yang','鬼金羊','damage_reduction',[0.1,0.2],'比例','5%～25%',0.05,(0,1),'基础伤害乘 (1−减免比例) 后取整。'),
    ('yi_huo_she','翼火蛇','hold_head_bonus_ms',[10,10],'ms','5～20',5,(0,100),'只给 Hold 头部四档窗口追加同样毫秒数。'),
    ('yi_huo_she','翼火蛇','hold_sustain_bonus_ms',[20,20],'ms','10～40',10,(0,200),'追加 Hold 断持宽限。'),
    ('yi_huo_she','翼火蛇','hold_grade_boost',[0,1],'级','0 或 1',1,(0,3),'整条 Hold 最终得分等级提升；机械失败与伤害不被免除。'),
]:
    for tier, value in zip(['base','advanced'],values):
        rows.append(dict(section='06 随从',target=f'pet:{pet}:{tier}',key=key,
                         name=name+('·基础' if tier=='base' else '·进阶')+' '+{'perfect_score_bonus':'得分加成','damage_reduction':'减伤','hold_head_bonus_ms':'头部宽限','hold_sustain_bonus_ms':'断持宽限','hold_grade_boost':'判定提升'}[key],
                         default=value,unit=unit,suggested=recommended,step=step,meaning=meaning,
                         minimum=limits[0],maximum=limits[1],type='int' if isinstance(value,int) else 'float',
                         source=f'content/pets/pet_{pet}.tres'))

for key,name,value,unit,suggested,step,low,high,meaning in [
    ('enabled','波浪动画',True,'开关','开启',1,0,1,'关闭后原画静止；只影响背景表现。'),
    ('vortex_inner_radius_px','漩涡内半径',88.0,'设计 px','88～100',1,80,110,'中央留白的基准尺度；整体弧面向外调整，不裁切水体。'),
    ('vortex_width_px','浪身宽度',112.0,'设计 px','100～130',2,80,150,'向浪身外缘增加厚度；入口下缘保持平顺上行。'),
    ('vortex_foam_strength','细沫强度',0.65,'比例','50%～75%',0.05,0,1,'沿卷流前进的骨白细水纹混合强度。'),
    ('vortex_flow_speed_px_sec','卷流速度',96.0,'设计 px/s','80～120',4,0,180,'水纹沿厚浪弧线连续前进的速度；浪缘略快，抵达尖端逐渐消散。'),
    ('vortex_beat_push_px','每拍推进',1.25,'设计 px/拍','0～2',0.05,0,3,'每拍前 0.4 拍柔和增加的路程；0 关闭提速，基础卷流继续。'),
    ('flow_enabled','基底水流',True,'开关','开启',1,0,1,'关闭后基底原纹固定，活动浪头继续播放；总动画关闭时仍恢复完整原画。'),
    ('flow_speed_px_sec','基底流速',60.0,'设计 px/s','48～72',2,0,100,'内部色带的基准流速；局部随水带宽窄变化，不随 BPM 加速。'),
    ('flow_strength','原纹流动强度',0.80,'比例','65%～90%',0.05,0,1,'内部流动颜色的混合比例；不改变透明轮廓和水带厚度。'),
    ('streak_strength','细水纹强度',0.24,'比例','18%～30%',0.01,0,0.4,'原画色细水线的峰值混合比例；0 只关闭细纹，不影响原纹流动。'),
]:
    rows.append(dict(section='07 分界线表现',target='boundary',key=key,name=name,default=value,
                     unit=unit,suggested=suggested,step=step,minimum=low,maximum=high,meaning=meaning,
                     type='bool' if isinstance(value,bool) else ('int' if isinstance(value,int) else 'float'),source='src/content/resources/boundary_motion_style.gd'))

out=ROOT/'content/rules/planning_parameters.json'
# 角色移动的表现目录单独维护，重建玩法基线时保留这些字段。
if out.exists():
    rows.extend(r for r in json.loads(out.read_text(encoding='utf-8')) if r['target'] in ['actors','boss','ui_flame','ui_guides','judgment'] or r['target'].startswith('reward:'))
out.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'{len(rows)} 个可编辑参数')

def display(value, unit):
    if isinstance(value, bool): return '0（关闭）' if not value else '1（开启）'
    return f'{value*100:g}%' if unit=='比例' else str(value)

directory=ROOT/'docs/planning'
directory.mkdir(parents=True,exist_ok=True)
for pet_page, filename, title in [(False,'01-全局数值.md','全局手感与数值'),(True,'02-随从数值.md','随从技能数值')]:
    selected=[r for r in rows if r['target'] not in ['boundary','actors','boss','ui_flame','ui_guides','judgment'] and r['target'].startswith('pet:')==pet_page]
    lines=[f'# {title}', '', '基线：2026-09-14。表格 B 列可直接修改；下列区间是试调建议，允许输入范围另列。实际值以工作簿当前值为准。', '']
    if pet_page:
        lines+=['随从中性配置的所有加成默认均为 0。下表是三只正式随从的两阶资源覆盖；只有已装备的形态生效，进阶不与基础叠加。技能描述原文未改动。', '',
                '鬼金羊默认使每组 20 点伤害变为 18 / 16 点，100 魂火分别在第 6 / 7 组耗尽。翼火蛇两阶头部窗口实际为 55/100/145/190 ms，断持宽限 120 ms；进阶对最终得分等级提一级，失败伤害仍保留。', '']
    for section in dict.fromkeys(r['section'] for r in selected):
        lines += [f'## {section}', '', '| 参数／字段 | 原型默认 | 单位 | 建议区间；步长 | 允许范围 |', '| --- | ---: | --- | --- | --- |']
        part=[r for r in selected if r['section']==section]
        for r in part:
            lines.append(f"| {r['name']}<br>`{r['key']}` | {display(r['default'],r['unit'])} | {r['unit']} | {r['suggested']}；{display(r['step'],r['unit'])} | {r['minimum']}～{r['maximum']} |")
        lines += ['', '### 含义与生效位置', '']
        for r in part:
            lines.append(f"- **{r['name']}**：{r['meaning']} 来源：`{r['source']}`。")
        lines += ['']
    if not pet_page:
        lines+=['## 判定边界与计分公式', '',
                '误差取绝对值；默认 `≤45 ms` 为 Perfect，`45～90 ms` 为 Good，`90～135 ms` 为 Pass（后两档不含左端点）。超过 Pass 不能主动命中；未命中音符在晚侧超过 180 ms 后记 Miss。各阈值端点包含在内，超时在下一微秒结算。Hold 加成仅影响 Hold。', '',
                '`本次得分 = round(档位基础分 × lerp(1, 最高倍率, clamp((Combo−1)/倍率爬升步数,0,1)))`。Miss 清零 Combo 并给 miss_score。普通 Hold 最终结算一次；Tuning 按编译后的判定单位结算，同组双侧滑条可以合成一个单位；Ghost 不追加单位。', '',
                '调频每程到规定尾点检查完成度与持有：默认 ≥97% 为 Perfect、≥90% 为 Good、≥80% 为 Pass，其余或松开对应钟为 Miss。多程、双侧组合取最差分项，不提供尾点后的晚到窗口；滑条自身不扣血。新写谱器每对相邻节点适配为一段。', '',
                '声波默认 2400 px/s、基频 3 Hz，匀频载波间距约为 800 设计 px；1 Hz 约 2400 px，7 Hz 约 343 px。频率和速度同时改变时，应看它们的比值与真实交点，不只看某一个参数。', '']
    (directory/filename).write_text('\n'.join(lines).rstrip()+'\n',encoding='utf-8')
