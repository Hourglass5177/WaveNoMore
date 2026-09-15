"""正式谱保底制作：只添加 BOSS 对象、入场轨道和明确绑定，不改谱面。"""
from pathlib import Path
import json, zipfile, shutil
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'Levels/output/保底关卡'
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def write(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
def seconds(tick,timing):
    total=0.;events=timing['tempo_events']
    for i,e in enumerate(events):
        end=min(tick,events[i+1]['tick']) if i+1<len(events) else tick
        if end>e['tick']:total+=(end-e['tick'])/timing['ppq']*60/e['bpm']
        if end>=tick:break
    return total+timing.get('first_beat_offset_ms',0)/1000
summary=[]
for number,song_name,visual,title in [(1,'教程#3','bat','第一关 · 蝙蝠'),(2,'第二关#2','snake','第二关 · 蛇')]:
    dest=OUT/f'level_{number}';dest.mkdir(parents=True,exist_ok=True)
    if number==2:
        with zipfile.ZipFile('F:/Downloads/level_2.zip') as z:
            for item in z.infolist():
                target=(dest/item.filename).resolve()
                if not target.is_relative_to(dest.resolve()):raise ValueError(item.filename)
                if not item.is_dir():target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(z.read(item))
        level=read(dest/'level.json');show=read(dest/'show.json')
    else:
        level=read(ROOT/'Levels/output/boss-user-repro/tutorial_1/level.json')
        level.update(level_id='fallback_level_1',title=title)
        show={'format':'minghe-show','format_version':1,'objects':[],'tracks':[],'bindings':[],'scene_cues':[],'sequences':[]}
    song=ROOT/'Charts/charts/正式谱'/song_name
    for source in song.rglob('*'):
        if source.is_file() and not source.name.endswith(('.bak','.import')) and 'editor' not in source.relative_to(song).parts:
            target=dest/'song'/source.relative_to(song);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
    chart=read(song/'charts/normal.json');notes=[n for n in chart['notes']+chart.get('ghost_events',[]) if n.get('boss')]
    first=min(seconds(n['tick'],chart['timing']) for n in notes);arrival=max(0,first-7)
    oid=f'fallback_boss_{number}'
    obj={'id':oid,'name':title.split(' · ')[1]+' BOSS','type':'actor','asset':'','animation':'','parent_id':'','layer':'world','depth':0,'occlusion_depth':0,'occlusion_order':'none','hidden':False,'locked':False,'fields':{'position':[960,250],'scale':[.85,.85],'rotation':0,'opacity':1,'color':'ffffffff','visible':True,'size':[560,100]},'boss':{'visual':visual,'health_ratio':.8,'flight_speed':600,'spread_deg':30}}
    show['objects'].append(obj)
    def track(prop,values):
        keys=[{'id':f'{oid}_{prop}_{i}','time_us':round(t*1000000),'value':v,'interpolation':'linear','in_handle':[.666667,.666667],'out_handle':[.333333,.333333]} for i,(t,v) in enumerate(values)]
        return {'id':f'{oid}_{prop}','object_id':oid,'type':'property','property':prop,'section':'song','difficulties':[],'muted':False,'locked':False,'keys':keys,'clips':[]}
    show['tracks'] += [track('position',[(0,[960,-340]),(arrival,[960,-340]),(arrival+1.4,[960,250])]),track('opacity',[(0,0),(arrival,0),(arrival+1.2,1)])]
    show['bindings'].append({'id':f'{oid}_attack','object_id':oid,'difficulty':'normal','note_ids':[n['id'] for n in notes],'action_mode':'auto','action':'attack_start','rate':1,'release_sec':.45,'return_us':1000000,'action_duration_us':1000000,'path_mode':'auto','life_anchor':'life','death_anchor':'death'})
    write(dest/'level.json',level);write(dest/'show.json',show)
    write(dest/'workspace.json',{'section':'song','time_us':round(arrival*1000000)})
    summary.append({'level':number,'boss':visual,'notes':len(notes),'enter_sec':round(arrival,3),'first_judgment_sec':round(first,3),'scene_cues':show.get('scene_cues',[])})
write(OUT/'制作摘要.json',{'completed':summary,'level_3':'等待场景后制作'})
print(json.dumps(summary,ensure_ascii=False))
