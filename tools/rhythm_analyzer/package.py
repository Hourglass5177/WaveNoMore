"""收集依赖许可并显式打包，禁止把输出目录中的用户工程整体加入 ZIP。"""
from importlib import metadata
from pathlib import Path
import shutil
import sys
import zipfile

root = Path(__file__).resolve().parents[2]
output = root / 'builds/chart-studio'
with_game = '--with-game' in sys.argv
if with_game and not (output / 'game/minghe.exe').is_file():
    raise SystemExit('缺少配套 game/minghe.exe，请先显式构建游戏')
licenses = output / 'rhythm_analyzer/licenses'
licenses.mkdir(parents=True, exist_ok=True)
for distribution in metadata.distributions():
    name = distribution.metadata['Name']
    for file in distribution.files or []:
        if any(word in file.name.lower() for word in ('license', 'copying', 'notice')):
            source = Path(distribution.locate_file(file))
            if source.is_file() and source.suffix.lower() not in ('.py', '.pyc', '.pyd'):
                destination = licenses / name / str(file).replace('../', '').replace('..\\', '')
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination)
python_license = Path(sys.base_prefix) / 'LICENSE.txt'
if python_license.exists():
    shutil.copy2(python_license, licenses / 'Python-LICENSE.txt')
shutil.copy2(root / 'tools/rhythm_analyzer/THIRD-PARTY.md', licenses / 'THIRD-PARTY.md')
shutil.copy2(root / 'tools/rhythm_analyzer/requirements-lock.txt', licenses / 'requirements-lock.txt')
guide = (root / 'docs/chart-editor-guide.md').read_text(encoding='utf-8')
guide = guide.replace('(chart-editor-progress.md)', '(docs/chart-editor-progress.md)')
guide = guide.replace('(chart-editor-tuning.md)', '(docs/chart-editor-tuning.md)')
guide = guide.replace('(local-chart-playtest.md)', '(docs/local-chart-playtest.md)')
(output / '写谱器使用说明.md').write_text(guide, encoding='utf-8')
# 运行目录与开发包共用当前文档清单，不把本地历史和用户工程扫入包中。
documents = ('local-chart-playtest.md', 'local-chart-validation.md', 'chart-editor-progress.md', 'chart-editor-interfaces.md',
             'chart-editor-rhythm-analysis.md', 'chart-editor-ui-review.md',
             'chart-editor-timing-2026-09.md', 'rhythm-fit-2026-09.md',
             'game-audio-calibration-2026-09.md', 'chart-editor-cue-measurement.json',
             'chart-editor-cue-main-thread-baseline.json',
             'chart-editor-audio-measurement.json', 'chart-editor-audio-longterm.json',
             'chart-editor-performance.json', 'chart-editor-tuning.md',
             'chart-editor-tuning-validation.md', 'chart-editor-tuning-edit-performance.json',
             'chart-editor-seek-performance.json',
             'chart-editor-tuning-performance.json', 'chart-editor-tuning-short-preview.json', 'tuning-su-game-editor-handoff-2026-09-08.md',
             'develop-merge-review-2026-09-08.md')
(output / 'docs').mkdir(exist_ok=True)
for name in documents:
    shutil.copy2(root / 'docs' / name, output / 'docs' / name)
packaged_tuning = output / 'docs/chart-editor-tuning.md'
packaged_tuning.write_text(packaged_tuning.read_text(encoding='utf-8').replace(
    '../tests/editor/fixtures/tuning/charts/normal.json', '../Tuning示例工程/charts/normal.json'), encoding='utf-8')

# 新示例使用独立目录名，只收集明确文件，既有用户项目和旧示例均不改动。
tuning_example = root / 'tests/editor/fixtures/tuning'
for relative in ('song.json', 'charts/normal.json', 'audio/song.wav'):
    destination = output / 'Tuning示例工程' / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(tuning_example / relative, destination)
screenshots = ('workspace-1280.png', 'workspace-1440.png', 'workspace-1920.png', 'ghost-three.png', 'preview-loading.png')
(output / 'docs/screenshots').mkdir(exist_ok=True)
for name in screenshots:
    shutil.copy2(root / 'builds/tuning-review' / name, output / 'docs/screenshots' / ('tuning-' + name))

trial_screenshots = ('local-1280.png', 'local-1440.png', 'local-1920.png', 'select-1280.png')
for name in trial_screenshots:
    shutil.copy2(root / 'docs/screenshots' / name, output / 'docs/screenshots' / name)

archive = root / 'builds/minghe-chart-studio-dev.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
    for name in ('minghe-chart-studio.exe', '写谱器使用说明.md'):
        bundle.write(output / name, name)
    if with_game:
        bundle.write(output / 'game/minghe.exe', 'game/minghe.exe')
    for name in documents:
        bundle.write(output / 'docs' / name, 'docs/' + name)
    for name in trial_screenshots:
        bundle.write(output / 'docs/screenshots' / name, 'docs/screenshots/' + name)
    for name in screenshots:
        bundle.write(output / 'docs/screenshots' / ('tuning-' + name), 'docs/screenshots/tuning-' + name)
    for path in (output / 'rhythm_analyzer').rglob('*'):
        if path.is_file():
            bundle.write(path, path.relative_to(output))
    fixture = root / 'tests/editor/fixtures/training'
    for relative in ('song.json', 'charts/normal.json', 'audio/song.wav'):
        bundle.write(fixture / relative, '示例工程/' + relative)
        bundle.write(tuning_example / relative, 'Tuning示例工程/' + relative)
print(f'{archive}\nZIP bytes: {archive.stat().st_size}')
