"""收集依赖许可并显式打包，禁止把输出目录中的用户工程整体加入 ZIP。"""
from importlib import metadata
from pathlib import Path
import shutil
import sys
import zipfile

root = Path(__file__).resolve().parents[2]
output = root / 'builds/chart-studio'
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
shutil.copy2(root / 'docs/chart-editor-guide.md', output / '写谱器使用说明.md')
archive = root / 'builds/minghe-chart-studio-dev.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
    for name in ('minghe-chart-studio.exe', '写谱器使用说明.md'):
        bundle.write(output / name, name)
    for path in (output / 'rhythm_analyzer').rglob('*'):
        if path.is_file():
            bundle.write(path, path.relative_to(output))
    fixture = root / 'tests/editor/fixtures/training'
    for relative in ('song.json', 'charts/normal.json', 'audio/song.wav'):
        bundle.write(fixture / relative, '示例工程/' + relative)
print(f'{archive}\nZIP bytes: {archive.stat().st_size}')
