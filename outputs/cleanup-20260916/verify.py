"""回收后核对保留文件、回收站原路径记录和文档链接；不恢复或删除文件。"""
import json,os,struct,subprocess,re
from pathlib import Path
from urllib.parse import unquote
from prepare import ROOT,OUT,sha,dump

manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
entries=manifest['entries']
results=[json.loads(s) for s in (OUT/'recycle-results.jsonl').read_text(encoding='utf-8-sig').splitlines() if s.strip()]
recycled={}
binroot=Path('E:/$Recycle.Bin')
for sid in binroot.iterdir():
 try:
  for p in sid.glob('$I*'):
   try:
    b=p.read_bytes();v=struct.unpack_from('<Q',b)[0]
    if v==2:
     length=struct.unpack_from('<I',b,24)[0];original=b[28:28+length*2].decode('utf-16-le').rstrip('\0')
    elif v==1:original=b[24:].decode('utf-16-le').rstrip('\0')
    else:continue
    payload=p.with_name('$R'+p.name[2:])
    if payload.exists():recycled[original.casefold()]={'metadata':str(p),'payload':str(payload)}
   except (OSError,ValueError,struct.error,UnicodeError):pass
 except PermissionError:pass

missing_receipts=[];remaining=[];receipt_map=[]
completed_paths={r['path'] for r in results if r['result']=='已回收'}
for e in entries:
 p=Path(e['path'])
 if p.exists():remaining.append(str(p))
 rec=recycled.get(str(p).casefold())
 if not rec and str(p) in completed_paths:missing_receipts.append(str(p))
 elif rec:receipt_map.append({'original':str(p),**rec})
dump('recycle-receipts.json',receipt_map)
edits=json.loads((OUT/'document-edits.json').read_text(encoding='utf-8'))
baseline=json.loads((OUT/'protected-before.json').read_text(encoding='utf-8'))
missing=[];changed=[];ok=0
for e in baseline:
 p=Path(e['path']);expected=edits.get(str(p),{}).get('after',e['sha256'])
 if not p.exists():missing.append(str(p))
 elif sha(p)!=expected:changed.append(str(p))
 else:ok+=1
print('保留文件',ok,'缺失',len(missing),'意外变化',len(changed),flush=True)

link=re.compile(r'!?\[[^\]\n]*\]\(([^)\n]+)\)')
def broken(p,s):
 result=[]
 for url in link.findall(s):
  target=url.strip().strip('<>')
  if re.match(r'^[a-zA-Z]+://|^#',target):continue
  target=unquote(target.split('#')[0]);q=Path(os.path.abspath(p.parent/target))
  if not q.exists():result.append(url)
 return result
new_broken=[];old_broken=[]
for name in edits:
 p=Path(name);backup=OUT/'document-backups'/p.relative_to(ROOT)
 old=set(link.findall(backup.read_text(encoding='utf-8-sig')))
 for url in broken(p,p.read_text(encoding='utf-8-sig')):
  (old_broken if url in old else new_broken).append({'file':name,'target':url})
git=subprocess.check_output(['git','-C',str(ROOT/'Game'),'-c','core.quotepath=false','status','--short','--untracked-files=all'])
(OUT/'git-after.txt').write_bytes(git)
worktrees=subprocess.check_output(['git','-C',str(ROOT/'Game'),'worktree','list','--porcelain'])
same_worktrees=worktrees==(OUT/'worktrees-before.txt').read_bytes()
report={'planned_items':len(entries),'completed_items':sum(r['result']=='已回收' for r in results),
 'files':sum(r['files'] for r in results if r['result']=='已回收'),'bytes':sum(r['bytes'] for r in results if r['result']=='已回收'),
 'recycle_receipts':len(receipt_map),'missing_receipts':missing_receipts,'remaining':remaining,
 'protected_verified':ok,'protected_missing':missing,'protected_unexpected_changes':changed,
 'document_changes':len(edits),'new_broken_links':new_broken,'preexisting_broken_links':old_broken,
 'worktrees_unchanged':same_worktrees,'excluded_links':manifest['excluded_links']}
dump('verification.json',report)
print(json.dumps({k:len(v) if isinstance(v,list) else v for k,v in report.items()},ensure_ascii=False),flush=True)
