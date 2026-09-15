"""BOSS 动作编排。位移以最终 560 px 审看尺寸描述，再换回骨骼局部坐标。"""
import math
import copy
import numpy as np

def build_animations(d, source, config, value, smooth, matrices):
    key=config['id'];kind='goat' if key.startswith('goat') else key
    idle=source['animations'][config['idle']]
    names=[b['name'] for b in source['bones']]
    unit=config['unit']
    def rest(t=0):
        pose={n:{'rotate':0.,'x':0.,'y':0.,'sx':1.,'sy':1.} for n in names}
        for n,tracks in idle['bones'].items():
            for k,ks in tracks.items():
                fields=['angle'] if k=='rotate' else ['x','y'];default=[0] if k=='rotate' else ([1,1] if k=='scale' else [0,0])
                vv=value(ks,t%4,fields,default,k=='rotate')
                pose[n].update(dict(zip(['rotate'] if k=='rotate' else (['sx','sy'] if k=='scale' else (['shx','shy'] if k=='shear' else ['x','y'])),vv)))
        return pose
    base=rest();worlds=matrices(source['bones'],base)
    parents={b['name']:b.get('parent') for b in source['bones']}
    def move(p,n,dx,dy):
        # 参数 Y 向上；父骨骼可能旋转近 90°，不能直接把画面位移写入局部 X/Y。
        parent=parents[n];m=worlds[parent][:2,:2] if parent else np.eye(2)
        v=np.linalg.solve(m,np.array([dx,dy])/unit)
        p[n]['x']+=v[0];p[n]['y']+=v[1]
    def setr(p,n,x):p[n]['rotate']+=x
    def oscillation(t,period,delay=0):return math.sin(math.tau*(t-delay)/period)
    def pose(phase,t):
        p=copy.deepcopy(base)
        if phase=='hurt':p={n:{'rotate':0.,'x':0.,'y':0.,'sx':1.,'sy':1.} for n in names}
        attack=phase in ['attack_start','attack_loop','attack_end']
        if attack:
            if phase=='attack_start':
                u=t/config['start'];charge=smooth(0,.60,u)*(1-smooth(.64,1,u));release=smooth(.60,1,u);clock=0.
            elif phase=='attack_loop':charge=0.;release=1.;clock=t
            else:charge=0.;release=1-smooth(0,config['end'],t);clock=0.
            if kind=='bat':
                beat=oscillation(clock,config['loop']/2)*release
                move(p,'root',0,-18*charge+30*release+6*beat)
                for n,sign in [('bone5',1),('bone6',-1)]:
                    setr(p,n,sign*(18*charge-24*release+7*beat));p[n]['sx']*=1+.05*release
                for n,sign in [('bone11',1),('bone8',-1)]:setr(p,n,sign*(6*charge-5*release+4*oscillation(clock,.6,.07)*release))
                for n,sign in [('bone3',1),('bone4',-1),('bone29',1),('bone31',-1)]:setr(p,n,sign*(4*charge+3*oscillation(clock,1.2,.12)*release))
                setr(p,'bone32',3*oscillation(clock,1.2,.15)*release)
            elif kind=='snake':
                # 三颈独立前探；盘曲身体只做少量压缩，不旋动贯穿全身的长骨链。
                for n,dx,dy,angle,delay in [('bone24',-12,58,-6,0),('bone18',-44,32,-7,.12),('bone13',48,30,7,.24)]:
                    r=release; bob=oscillation(clock,config['loop'],delay)*r
                    move(p,n,dx*r-dx*.3*charge,dy*r-20*charge+5*bob)
                    setr(p,n,angle*r+3*bob)
                for n,sgn in [('bone17',-1),('bone23',1),('bone27',1)]:setr(p,n,sgn*8*release)
                for i,n in enumerate(['bone30','bone31','bone32','bone33','bone34']):setr(p,n,2.2*oscillation(clock,config['loop'],i*.07)*release)
                p['root']['sx']*=1-.035*charge+.015*release
            else:
                move(p,'root',0,-18*charge+30*release+4*oscillation(clock,config['loop'])*release)
                setr(p,'bone',-9*charge+6*release+1.5*oscillation(clock,config['loop'])*release)
                for n,sgn in [('bone10',-1),('bone19',1)]:setr(p,n,sgn*(-12*charge+13*release+3*oscillation(clock,config['loop'],.13)*release))
                for i,n in enumerate(['bone12','bone15','bone18','bone21','bone22','bone25','bone26']):setr(p,n,5*oscillation(clock,config['loop'],.16+i*.02)*release)
        elif phase=='hurt':
            end=config['hurt'];pulse=smooth(0,.07,t)*(1-smooth(.09,end,t))
            late=smooth(.04,.12,t)*(1-smooth(.15,end,t))
            if kind=='bat':
                move(p,'root',0,-20*pulse)
                setr(p,'bone5',-12*pulse);setr(p,'bone6',12*pulse)
                setr(p,'bone11',-5*late);setr(p,'bone8',5*late)
            elif kind=='snake':
                for n,delay in [('bone24',0),('bone18',.05),('bone13',.10)]:
                    q=smooth(delay,delay+.06,t)*(1-smooth(delay+.08,end,t));move(p,n,0,-22*q)
            else:
                move(p,'root',0,-16*pulse);setr(p,'bone',-7*pulse)
                setr(p,'bone10',-9*late);setr(p,'bone19',9*late)
        elif phase=='phase_break':
            recoil=smooth(0,.45,t)*(1-smooth(.45,1.25,t))
            wake=smooth(1.05,1.85,t)*(1-smooth(2.65,3.,t))
            move(p,'root',0,-24*recoil+9*wake);setr(p,'bone',-10*recoil+3*wake)
            for n,sgn in [('bone10',-1),('bone19',1)]:setr(p,n,sgn*(12*recoil+7*wake))
            for i,n in enumerate(['bone12','bone15','bone18','bone21','bone22','bone25','bone26']):
                late=smooth(.1,.6,t)*(1-smooth(1.7,2.95,t))
                setr(p,n,8*late*math.cos(i*.45))
        elif phase=='death':
            if kind=='bat':
                recoil=smooth(0,.30,t)*(1-smooth(.55,1.15,t));open_=smooth(.55,1.15,t);fall=smooth(1.25,3.2,t)
                move(p,'root',0,-26*recoil+65*open_-80*fall);setr(p,'root',-7*recoil)
                for n,sgn in [('bone5',1),('bone6',-1)]:
                    setr(p,n,sgn*(24*recoil-32*open_));p[n]['sx']*=1+.09*open_
                for n,sgn in [('bone11',1),('bone8',-1)]:setr(p,n,sgn*(8*recoil-7*open_))
                setr(p,'bone3',-12*recoil);setr(p,'bone4',8*recoil)
            elif kind=='snake':
                recoil=smooth(0,.45,t)*(1-smooth(.65,1.25,t));fall=smooth(1.65,3.6,t)
                for n,dx,dy,sgn,delay in [('bone24',-18,85,-1,0),('bone18',-60,62,-1,.08),('bone13',65,72,1,.16)]:
                    rise=smooth(.65+delay,1.25,t);move(p,n,dx*rise,dy*rise-28*recoil-80*fall);setr(p,n,sgn*(12*rise-7*recoil))
                move(p,'root',0,-22*fall);p['root']['sx']*=1-.04*recoil+.04*smooth(.65,1.25,t)
            else:
                recoil=smooth(0,.35,t)*(1-smooth(.40,.70,t));rise=smooth(.70,2.10,t)
                # 头骨在裂解交接点定姿；之后由同一切分图中的骨片继续运动。
                move(p,'root',0,-30*recoil+70*rise);setr(p,'bone',-15*recoil)
                setr(p,'bone10',-22*rise);setr(p,'bone19',22*rise)
                for i,n in enumerate(['bone12','bone15','bone18','bone21','bone22','bone25','bone26']):
                    setr(p,n,12*recoil-12*smooth(.85+i*.025,2.10,t))
        return p

    # 全部基础动作给叠加属性明确基准；新动作每帧写全姿态，受击只保留有变化的骨骼。
    for a in d['animations'].values():
        for n in names:
            a['bones'].setdefault(n,{})
            for prop,frame in [('rotate',{'value':0}),('translate',{'x':0,'y':0}),('scale',{'x':1,'y':1}),('shear',{'x':0,'y':0})]:a['bones'][n].setdefault(prop,[frame])
    phases=[('attack_start',config['start']),('attack_loop',config['loop']),('attack_end',config['end']),('hurt',config['hurt']),('death',config['death'])]
    if kind=='goat':phases.append(('phase_break',3.0))
    for phase,end in phases:
        times=sorted({round(i/60,7) for i in range(math.ceil(end*60))}|{end})
        tracks={n:{'rotate':[],'translate':[],'scale':[]} for n in names}
        for t in times:
            p=pose(phase,t)
            for n,q in p.items():
                tracks[n]['rotate'].append({'time':t,'value':round(float(q['rotate']),6)})
                tracks[n]['translate'].append({'time':t,'x':round(float(q['x']),6),'y':round(float(q['y']),6)})
                tracks[n]['scale'].append({'time':t,'x':round(float(q['sx']),6),'y':round(float(q['sy']),6)})
        if phase=='hurt':
            for n in list(tracks):
                for prop in list(tracks[n]):
                    if all(all(v==(1 if prop=='scale' else 0) for k,v in f.items() if k!='time') for f in tracks[n][prop]):del tracks[n][prop]
                if not tracks[n]:del tracks[n]
        if phase!='hurt':
            for n in names:tracks[n]['shear']=[{'x':base[n].get('shx',0),'y':base[n].get('shy',0)}]
        d['animations'][phase]={'bones':tracks}
        # 写实眼球沿用已有网格形变，匹配新动作长度；亮起前后仍有瞳孔转动。
        if key=='goat_eye' and phase!='hurt':
            attachments=copy.deepcopy(d['animations'][config['idle']].get('attachments',{}))
            for slots in attachments.values():
                for ats in slots.values():
                    for timelines in ats.values():
                        for frames in timelines.values():
                            for f in frames:f['time']*=end/4
            d['animations'][phase]['attachments']=attachments
    return base,worlds
