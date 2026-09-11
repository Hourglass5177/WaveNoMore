"""沿用上一发布包的配套文件，用当前构建和文档制作新版；不扫描用户工程。"""
import argparse
from pathlib import Path
import shutil
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--version', required=True)
parser.add_argument('--base', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
runtime = root / 'builds/chart-studio'
prefix = f'冥河写谱器-v{args.version}'
archive = root / 'builds' / f'{prefix}-Windows.zip'

with zipfile.ZipFile(args.base) as previous:
    old_prefix = previous.namelist()[0].split('/')[0] + '/'
    entries = {entry.filename[len(old_prefix):]: entry for entry in previous.infolist() if not entry.is_dir()}
    replacements = {}
    # 两个导出目标各有自己的原生库，不能只带 EXE。
    for directory in ('', 'game/'):
        for name in ('minghe-chart-studio.exe' if not directory else 'minghe.exe',
                     'libspine_godot.windows.template_release.x86_64.dll', 'wnm_controller_haptics.dll'):
            relative = directory + name
            replacements[relative] = runtime / relative
    for relative in entries:
        if relative.startswith(('docs/', 'src/')) and (root / relative).is_file():
            replacements[relative] = root / relative
    for relative in ('docs/chart-studio-scenes.md', 'docs/chart-editor-interfaces.md',
                     'docs/tap-feedback-tuning-radius.md', 'docs/note-glow-2026-09.md',
                     'docs/screenshots/tap-feedback.png', 'docs/screenshots/tuning-radius.png'):
        replacements[relative] = root / relative

    guide = (root / 'docs/chart-editor-guide.md').read_text(encoding='utf-8')
    for name in ('chart-editor-progress.md', 'chart-editor-tuning.md', 'local-chart-playtest.md', 'chart-studio-scenes.md'):
        guide = guide.replace(f'({name})', f'(docs/{name})')
    gameplay = previous.read(entries['音符与玩法介绍.md']).decode('utf-8').replace('\r\r\n', '\n').replace('\r\n', '\n')
    # 以最近一版为基础再次打包时，不重复追加上一版已有的说明。
    for heading, paragraph in (
        ('### Tap：点一下', 'Tap 成功命中时立即隐藏外圈和双押白光，留下短促的命中印记。本体以原亮度的 45% 继续移动，声波接触后原地消散。'),
        ('### Ghost：调频过程中的奖励', '单选一条 Tuning，在右侧关闭“自动半径”，即可调整“半径（px）”。初值取首段当前半径，箭头每次微调 1 px。距离从画面中心量到轨道中心线，以 1920×1080 设计画布为准；整条路径共用半径，生死两侧分别设置。'),
    ):
        if paragraph not in gameplay:
            gameplay = gameplay.replace(heading, paragraph + '\n\n' + heading)
    gameplay = gameplay.replace('多节点 Tuning 的预览目前分段播放，接合处的预告和圆弧半径可能变化。',
        '多节点 Tuning 的预览目前分段播放。自动模式保留各段原半径；设置自定义半径后，各段位于同一圆周。')
    tuning = (root / 'docs/chart-editor-tuning.md').read_text(encoding='utf-8').replace(
        '../tests/editor/fixtures/tuning/charts/normal.json', '../Tuning示例工程/charts/normal.json')
    texts = {'写谱器使用说明.md': guide, '音符与玩法介绍.md': gameplay,
             '版本更新.md': (root / f'docs/chart-studio-v{args.version}.md').read_text(encoding='utf-8'),
             'docs/chart-editor-tuning.md': tuning}
    # 同步运行目录中的程序说明；test、output 和用户示例不做任何写入。
    for relative, content in texts.items():
        (runtime / relative).write_text(content, encoding='utf-8', newline='\n')
    for relative, source in replacements.items():
        if relative.startswith('docs/') and relative not in texts:
            destination = runtime / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        for relative in sorted(entries.keys() | replacements.keys() | texts.keys()):
            target = f'{prefix}/{relative}'
            if relative in texts:
                bundle.writestr(target, texts[relative].encode('utf-8'))
            elif relative in replacements:
                bundle.write(replacements[relative], target)
            else:
                # 流式沿用模型、依赖许可和已发布示例，避免复制整份解压目录。
                with previous.open(entries[relative]) as source, bundle.open(target, 'w') as destination:
                    shutil.copyfileobj(source, destination)
print(f'{archive}\n{archive.stat().st_size / 1048576:.1f} MiB')
