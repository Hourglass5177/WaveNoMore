"""独立读取 3.8 曲线，对照原生 4.3 骨骼采样；检查派生附件与参数保留。"""
import json
import numpy as np
from build_bosses import SOURCE,OUT,AUDIT,IDS,GAME,value,matrices
maximum=0.
for key,source_dir in IDS.items():
    source=json.loads(next((SOURCE/source_dir).rglob('*.json')).read_text(encoding='utf-8-sig'))
    config=json.loads((OUT/key/'animation.json').read_text(encoding='utf-8'))
    derived=json.loads((OUT/key/'boss.spine-json').read_text(encoding='utf-8'))
    skin=next((s for s in derived['skins'] if s['name']==key),derived['skins'][0])
    for sample in json.loads((AUDIT/(key+'-sampled-bones.json')).read_text()):
        pose={}
        for n,tracks in source['animations'][config['idle']]['bones'].items():
            pose[n]={}
            for prop,frames in tracks.items():
                fields=['angle'] if prop=='rotate' else ['x','y'];defaults=[0] if prop=='rotate' else ([1,1] if prop=='scale' else [0,0])
                vals=value(frames,sample['time'],fields,defaults,prop=='rotate')
                pose[n].update(zip(['rotate'] if prop=='rotate' else (['sx','sy'] if prop=='scale' else (['shx','shy'] if prop=='shear' else ['x','y'])),vals))
        for n,m in matrices(source['bones'],pose).items():
            unit=config['unit'];center=config['center']
            expected=np.array([m[0,0]*unit,-m[1,0]*unit,-m[0,1]*unit,m[1,1]*unit,500+(m[0,2]-center[0])*unit,450+(-m[1,2]-center[1])*unit])
            error=np.max(np.abs(expected-np.array(sample['bones'][n])))
            maximum=max(maximum,error)
            assert error<.15,(key,n,sample['time'],error)
    for clip in ['attack_start','attack_loop','attack_end','hurt','death']:assert clip in derived['animations']
    # 连续段闭合，原画网格和绘制顺序保留（新增眼部紧贴原眼之后）。
    for tracks in derived['animations']['attack_loop']['bones'].values():
        for frames in tracks.values():
            for field in frames[0]:
                if field!='time':assert abs(frames[0][field]-frames[-1][field])<1e-5
    for slot,ats in source['skins'][0]['attachments'].items():
        for name,attachment in ats.items():
            actual=skin['attachments'][slot][name]
            for field in ['vertices','uvs','triangles']:assert attachment[field]==actual[field]
    if key.startswith('goat'):
        seal=derived['animations']['seal_reveal']['slots']
        for name in config['seal_slots']:
            assert all(f['value']==0 for f in seal[name]['alpha'] if f.get('time',0)>=1.85),(name,'揭眼完成后仍有表层遮挡')
        names=['拆羊_2_0003_从选区','拆羊_2_0004_已插入图像','拆羊_2_0005_从选区']
        for i,n in enumerate(names):
            mask=skin['attachments'][f'eye_core_{i}'][f'eye_core_{i}']
            original=skin['attachments'][n][n]
            for field in ['vertices','uvs','triangles']:assert mask[field]==original[field]
            for anim in derived['animations'].values():
                slots=anim.get('attachments',{}).get(key,{})
                if n in slots:assert slots[n][n]==slots[f'eye_core_{i}'][f'eye_core_{i}']
    print(key,'source curves, mesh, eye masks, loop OK')
print('Maximum native/source bone difference:',maximum)
before=AUDIT/'planning-before-goat.xlsx'
if before.exists():
    import openpyxl
    a=openpyxl.load_workbook(before,read_only=True);b=openpyxl.load_workbook(GAME/'outputs/planning/策划参数.xlsx',read_only=True)
    for name in a.sheetnames:
        original=list(a[name].values);current=list(b[name].values)
        for row,values in enumerate(original):
            for col,v in enumerate(values):
                if name=='09 BOSS 表现' and col==6 and row in [5,6,7]:continue
                assert v==current[row][col],(name,row+1,col+1,v,current[row][col])
    print('Workbook current values/formulas preserved; only 3 BOSS descriptions changed')
