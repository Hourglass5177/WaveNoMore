"""将仍有用的接口说明并入现行文档，移除指向本次回收对象的链接。"""
import json,os,re
from pathlib import Path
from urllib.parse import unquote
from prepare import ROOT,OUT,DOCS,sha,dump

m=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
removed=[Path(e['path']) for e in m['entries']]
def deleted(p):return any(p==q or p.is_relative_to(q) for q in removed)
changed={}
def write(p,s):
 old=p.read_text(encoding='utf-8-sig')
 if old==s:return
 if str(p) not in changed:
  dest=OUT/'document-backups'/p.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True)
  if not dest.exists():dest.write_bytes(p.read_bytes())
  changed[str(p)]={'before':sha(p)}
 p.write_text(s,encoding='utf-8')
 changed[str(p)]['after']=sha(p)
def append(name,section):
 p=ROOT/'Game/docs'/name
 write(p,p.read_text(encoding='utf-8-sig').rstrip()+'\n\n'+section.strip()+'\n')

append('chart-editor-interfaces.md','''## 预览恢复与文件选择约定

预览先运行正式领域模拟并索引判定、接触和抵达，再恢复目标时刻仍可见的表现。活动 Hold 保留 120 Hz 运动积分，每 0.5 秒缓存运动状态，按序列化体积约 64 MiB 的预算淘汰；谱面编辑从最早受影响时刻失效缓存，规则、场景、谱面身份或时间偏移变化则清空。角色历史推进完成后才提交最终骨骼与网格。恢复期间允许取消及最新请求替换，不补播历史音效。

回归入口为 `tests/editor/run_preview_restore_tests.gd`、`run_preview_cache_tests.gd`、`run_preview_failure_tests.gd`；性能采样使用 `measure_preview_restore.gd`。现存长谱同步初始化和历史输入恢复仍可能耗时，不能把缓存接入视作所有压力谱已达流畅目标。

文件选择器使用 `*.json` 过滤，并提示选择 `song.json`。精确文件名过滤曾导致 Godot 对话框预选条目与文件名不同步；加载失败须显示具体原因。回归入口为 `tests/editor/run_open_dialog_tests.gd`。

发行程序使用构建时封装的策划参数，不读取运行目录遗留的外部工作簿；开发工程仍使用正式策划表。包内参数与加载回归见 `tests/editor/run_packaged_preview_tests.gd`。''')
append('local-chart-playtest.md','''## 后台试玩休眠

专用试玩仍运行、整个写谱器失焦且试听暂停时，冻结内嵌预览纹理和场景处理，将后台工具限制为至多 15 FPS。自动保存与进程监测继续；进行中的分批定位暂停，回到前台或试玩退出后恢复，不重新装谱。应用内弹窗不视为离开应用。

试玩进程状态约每 250 ms 查询一次，首次启动立即检查；这一周期只用于进程生命周期监测，不改变游戏输入、声音和判定更新频率。''')
append('level-editor-interfaces.md','''## 编辑与发行核对要点

- 素材导入采用独立路径保留同名原资源；SpriteFrames 的窗口拖放与普通动画导入共用转换及依赖收集，跳过空动作。预览无法读取时不创建不可见对象。骨骼图集与图片随包收集，导出后在隔离目录验证。
- 失败拖入、取消长任务和空选择确认不提交文档命令；失焦提交不得在属性控件已退出树后发生。旧模态窗口退出后才开启下一个窗口。读取无效工程时继续维护当前工程的自动恢复。
- 初始环境及换景应统一控制背景显示宿主，包含随机装饰实例；恢复基础环境不应改写素材自身显隐。
- Ghost 导出关联依赖 `GhostEvent` 的编辑器工具支持及同类型 `PackedStringArray` 初始化。实际发行资源必须保留 `tuning_ids`，验证应加载包内每关并执行 `StageRoot.load_stage`，不能只验证源资源或放宽校验。
- 保留真实入口回归：`run_level_entrypoint_tests.gd`、`run_level_reliability_tests.gd`、`run_level_spriteframes_drop_tests.gd`、`run_level_pack_restart_tests.gd`（均在 `tests/editor`）。验证成功需同时检查完成标记、退出码和引擎错误；真实触摸板、中文组合输入和跨屏 DPI 仍需要人工检查。''')
append('performance-and-resolution.md','''## Ghost 候选查询维护约定

查询按发射时间及完整批次处理波历史，结合波源到生成矩形的半径范围、对侧可相交半径区间排除无关圆对；足量预读在最早完整批次停止。小候选池直接检查间距，较大候选池用邻格缩小检查范围，但不改变排序、随机抽样及不足量处理。

无新载波时复用同一事件的候选结果，定位、配置变化和清场使缓存失效。保留 `tests/unit/domain/ghost_query_reference.gd` 的直接算法供坐标与顺序对照。单次函数测量不能替代整曲帧耗时；详细逐点日志仅用于诊断，避免同步输出造成长帧。''')
append('ghost-effects.md','''## 应用图标素材

`assets/ui/art/app_icon/ghost_logo.png` 为 1254×1254 RGBA 标识；`ghost_icon.png` 为 256×256 窗口图标，`ghost_icon.ico` 包含 16～256 px 七档 Windows 图标。它们来自用户 Ghost 原画的下缘柔光编辑，不替换局内眼睛贴图。项目图标与 Windows 导出图标分别配置 PNG 和 ICO；素材来源与使用权沿用原画归档。''')
append('launch-guides.md','''## 素材来源

耳机与控制器线稿由 OpenAI image_gen 生成；耳机使用用户选定的第一版。正式图位于 `assets/ui/art/boot/guides/headphones.png` 和 `controller.png`。中文、按键字母、引线与页面底色由 Godot 排版，审看大图不参与运行。''')

p=ROOT/'Game/docs/build-output.md'
write(p,'''# 构建与交付目录

## 当前保留

- `../Charts/`：写谱器、配套 `game/`、离线 `rhythm_analyzer/`、用户 `charts/` 和导出 `output/`。不要用发行包覆盖用户工程。
- `../Levels/`：关卡编辑器、配套 `game/`、用户工程及素材包。
- `builds/windows/`：现有独立游戏运行包。
- `../Levels/output/冥河，冥河！.zip`、`../Levels/output/冥河，冥河！（带开发工具版）.zip`：2026-09-16 参赛阶段保留的交付包，原样保存。带工具版内含一个旧上传状态文件，不影响本轮保留策略。
- `../Levels/output/保底关卡/`、`火-用户修改快照/`、`钟-用户修改快照/`：关卡成果与用户快照，继续保留。

编辑器运行目录和现有独立游戏不代表与参赛 ZIP 完全相同的构建；重新发布时应明确使用哪一版源工程。当前工作区有未提交改动，不能仅凭 HEAD 重现参赛包。

## 构建入口

在 Game 目录使用 Godot 4.7.2 和匹配模板，导出 `export_presets.cfg` 中的游戏、Chart Studio Windows、Level Studio Windows 预设。写谱器通常输出至 `../Charts/minghe-chart-studio.exe`，关卡编辑器输出至 `../Levels/minghe-level-studio.exe`；更新配套游戏时同步 `game/minghe.exe` 和必需原生 DLL。

完整写谱器打包工具为 `tools/package_chart_studio_release.py`。若使用 `--base`，必须指定仍存在的有效发行 ZIP；历史 v0.1.2～v0.1.5 独立 ZIP 已列入阶段清理，不应继续使用旧文档中的失效路径。用户谱面不自动收进发行包。

## 资源与核验

`assets/pv.ogv` 是 Git 忽略的本地运行资源，构建机仍须保留。源素材在仓库外 `../Assets/pv.ogv`。策划表位于 `outputs/planning/策划参数.xlsx`；发行程序使用构建时封装的参数，开发工程使用工作簿。

背景 shader UID 必须唯一；过去重复 UID 曾导致源工程正常而导出背景白屏。保留 `tests/visual/run_background_shader_tests.gd`，发行验证要检查包内资源和真实画面，不能只凭启动成功判断。Ghost 关联和原生 BOSS 同样需要在包内加载验证，见 [关卡素材接口](level-editor-interfaces.md)。

`build/`、`builds/` 的采样和临时产物可重新生成；`builds/worktrees/` 是 Git 工作树，不能按缓存递归删除。阶段清理记录保存于 `outputs/cleanup-20260916/`，不修改两个参赛 ZIP。
''')
p=ROOT/'AudioLab/README.md'
s=p.read_text(encoding='utf-8-sig').replace('当前依赖已安装；如重建 Toucan 环境','阶段清理已移除本地运行环境、下载缓存及模型；已有样音、脚本、版本记录与来源保留。如重建 Toucan 环境')
write(p,s)

# 仅改写指向本次回收对象的链接，已有其他失效链接留给核验清单。
redirect={ROOT/'Game/docs'/k:ROOT/'Game/docs'/v for k,v in DOCS.items()}
redirect[ROOT/'Docs/Program/《冥河，冥河！》Godot 4.6开发规划.md']=ROOT/'Docs/Program/《冥河，冥河！》Godot工程代码导览.md'
link=re.compile(r'(!?)\[([^\]\n]*)\]\(([^)\n]+)\)')
scan=[]
for base in ['Docs','Game/docs','Charts/docs','Levels/docs']:
 scan.extend((ROOT/base).rglob('*.md'))
for base in ['Game','Charts','Levels','AudioLab','Prototype']:
 scan.extend((ROOT/base).glob('*.md'))
link_edits=[]
for p in scan:
 if deleted(p):continue
 s=p.read_text(encoding='utf-8-sig')
 def replace(match):
  image,label,url=match.groups();target=url.strip().strip('<>')
  if re.match(r'^[a-zA-Z]+://|^#',target):return match.group()
  target=unquote(target.split('#')[0])
  q=Path(os.path.abspath(p.parent/target))
  if not deleted(q):return match.group()
  link_edits.append({'file':str(p),'old':url})
  if q in redirect:
   new=os.path.relpath(redirect[q],p.parent).replace('\\','/')
   return '['+label+']('+new+')'
  return label+'（历史产物已清理）'
 s=link.sub(replace,s)
 write(p,s)
dump('document-edits.json',changed)
dump('document-link-edits.json',link_edits)
print('文档更新',len(changed),'链接修正',len(link_edits))
