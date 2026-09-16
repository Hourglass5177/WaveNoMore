"""参赛阶段清理：生成明确清单，不移动文件；跳过所有目录链接。"""
import os, json, hashlib, subprocess
from pathlib import Path

ROOT = Path(r'E:\大学\MEMO\编钟音游')
OUT = ROOT / 'Game/outputs/cleanup-20260916'
DOCS = {
 'background-preview-fix.md':'build-output.md',
 'boundary-waves-validation.md':'boundary-motion.md',
 'branch-sync-2026-09-14.md':'build-output.md',
 'chart-editor-open-dialog-fix.md':'chart-editor-interfaces.md',
 'chart-editor-preview-performance-2026-09-14.md':'chart-editor-interfaces.md',
 'chart-editor-progress.md':'chart-editor-guide.md',
 'chart-editor-trial-performance-2026-09-09.md':'local-chart-playtest.md',
 'chart-editor-tuning-validation.md':'chart-editor-tuning.md',
 'chart-editor-ui-review.md':'chart-editor-guide.md',
 'chart-studio-v0.1.3.md':'chart-editor-release-notes.md',
 'chart-studio-v0.1.4.md':'chart-editor-release-notes.md',
 'develop-merge-review-2026-09-08.md':'chart-editor-tuning.md',
 'editor-branch-audit-2026-09-13.md':'level-editor-interfaces.md',
 'ghost-export-fix.md':'level-editor-interfaces.md',
 'ghost-icon-prompts.md':'ghost-effects.md',
 'launch-guides-prompts.md':'launch-guides.md',
 'level-editor-boss-combat-validation-2026-09-15.md':'level-editor-interfaces.md',
 'level-editor-boss-overview-playback-validation-2026-09-15.md':'level-editor-guide.md',
 'level-editor-entrypoint-audit-2026-09-15.md':'level-editor-interfaces.md',
 'level-editor-fixes-validation-2026-09-13.md':'level-editor-interfaces.md',
 'level-editor-initial-environment-validation-2026-09-15.md':'level-editor-interfaces.md',
 'level-editor-reliability-validation-2026-09-14.md':'level-editor-interfaces.md',
 'level-editor-spine-validation-2026-09-15.md':'level-editor-interfaces.md',
 'level-editor-validation.md':'level-editor-guide.md',
 'local-chart-validation.md':'local-chart-playtest.md',
 'note-effects-performance-2026-09.md':'performance-and-resolution.md',
 'note-effects-validation.md':'note-effects.md',
 'note-glow-2026-09.md':'note-effects.md',
 'note-wave-effects-validation.md':'note-effects.md',
 'pet-runtime-validation.md':'pet-system.md',
 'pet-validation.md':'pet-system.md',
 'tuning-su-game-editor-handoff-2026-09-08.md':'chart-editor-tuning.md',
}

def linked(p):
 return bool(p.lstat().st_file_attributes & 1024)

def files(p):
 if linked(p): return
 if p.is_file():
  yield p
 else:
  for e in p.iterdir(): yield from files(e)

def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  while b:=f.read(8*1024*1024): h.update(b)
 return h.hexdigest()

def dump(name,obj):
 (OUT/name).write_text(json.dumps(obj,ensure_ascii=False,indent=2),encoding='utf-8')

def prepare():
 OUT.mkdir(parents=True,exist_ok=True)
 if (OUT/'manifest.json').exists(): raise RuntimeError('清单已存在，不覆盖执行基线')
 selected=[]
 def add(rel,reason):
  p=ROOT/rel
  if p.exists(): selected.append((p,reason))
 for rel in ['Game/build','AudioLab/runtime','AudioLab/cache','AudioLab/models','AudioLab/__pycache__',
             'Charts/releases','Charts/archive/旧发行包','Levels/releases','tmp','.playwright-cli',
             'output/playwright','output/冥河-Web原型2.4.1-异拍拍频.zip','output/冥河-Web原型3.0.3-相纹调频.zip',
             'Game/outputs/boss-animation','Game/outputs/ui-flame','Game/outputs/launch-guides']:
  add(rel,'计划确认的旧发行包、实验依赖或审看中间产物')
 for p in (ROOT/'Game/builds').iterdir():
  if p.name not in ('worktrees','windows'): add(p.relative_to(ROOT),'旧构建或测试产物')
 keep={'冥河，冥河！.zip','冥河，冥河！（带开发工具版）.zip','保底关卡','火-用户修改快照','钟-用户修改快照'}
 for p in (ROOT/'Levels/output').iterdir():
  if p.name not in keep: add(p.relative_to(ROOT),'旧交付包、已核对的展开副本或测试产物')
 for name in DOCS: add('Game/docs/'+name,'阶段记录；现行内容并入 '+DOCS[name])
 for rel in ['Docs/Design/Web原型测试策划案与报告','Docs/Program/《冥河，冥河！》Godot 4.6开发规划.md','AudioLab/RESULTS.md','Prototype/VALIDATION.md']:
  add(rel,'已完成阶段的开发规划或验收报告；创作源文件保留')
 empty=ROOT/'.git-relocated-empty-20260903'
 if empty.exists() and not any(empty.iterdir()): add(empty.relative_to(ROOT),'已核对的空遗留目录')
 # 含链接的父目录不能整目录交给 Shell，拆分到不含链接的普通子项。
 links=[]; entries=[]
 def expand(p,reason):
  if linked(p): links.append(str(p));return
  inner=[]
  if p.is_dir():
   for d,ds,fs in os.walk(p,followlinks=False):
    for n in ds[:]:
     q=Path(d)/n
     if linked(q): inner.append(q);ds.remove(n)
    inner.extend(Path(d)/n for n in fs if linked(Path(d)/n))
  if inner:
   for q in p.iterdir(): expand(q,reason)
   return
  size=count=0
  for q in files(p): count+=1;size+=q.stat().st_size
  entries.append({'path':str(p),'files':count,'bytes':size,'reason':reason})
 for p,reason in selected: expand(p,reason)
 paths=[Path(e['path']) for e in entries]
 assert all(p!=ROOT and p.is_relative_to(ROOT) and not p.is_relative_to(OUT) for p in paths)
 dump('manifest.json',{'root':str(ROOT),'entries':entries,'excluded_links':links,'document_redirects':DOCS})
 (OUT/'git-before.txt').write_bytes(subprocess.check_output(['git','-C',str(ROOT/'Game'),'-c','core.quotepath=false','status','--short','--untracked-files=all']))
 (OUT/'worktrees-before.txt').write_bytes(subprocess.check_output(['git','-C',str(ROOT/'Game'),'worktree','list','--porcelain']))
 print('MANIFEST',len(entries),sum(e['files'] for e in entries),round(sum(e['bytes'] for e in entries)/1024**3,3),flush=True)
 excluded={str(p).casefold() for p in paths}
 baseline=[]
 skips=[OUT,ROOT/'Game/.git',ROOT/'Game/.godot',ROOT/'Game/builds/worktrees']
 def protect(p):
  if linked(p) or p in skips or str(p).casefold() in excluded:return
  if p.is_dir():
   for q in p.iterdir():protect(q)
  elif p.is_file():
   baseline.append({'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p)})
 protect(ROOT)
 dump('protected-before.json',baseline)
 # 只备份将编辑的说明文件；待回收的阶段报告由回收站保留原件。
 for base in ['Docs','Game/docs','Charts/docs','Levels/docs']:
  for p in (ROOT/base).rglob('*.md'):
   if any(p==q or p.is_relative_to(q) for q in paths):continue
   dest=OUT/'document-backups'/p.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(p.read_bytes())
 print('PROTECTED',len(baseline),flush=True)

if __name__=='__main__':prepare()
