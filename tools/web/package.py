"""封装已导出的 Web 目录，并附带本地试玩和服务器部署说明。"""
from pathlib import Path
import argparse
import re
import shutil
import zipfile

GAME = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--directory', type=Path, default=GAME / 'builds/web')
parser.add_argument('--output', type=Path)
args = parser.parse_args()
WEB = args.directory.resolve()
# 包名沿用工程版本，发布目录由调用者指定。
version = re.search(r'^config/version="([^"]+)"', (GAME / 'project.godot').read_text(encoding='utf-8'), re.MULTILINE).group(1)
required = ['index.html', 'index.js', 'index.wasm', 'index.side.wasm', 'index.pck',
            'libspine_godot.web.template_release.wasm32.wasm']
for name in required:
    if not (WEB / name).is_file():
        raise SystemExit('缺少导出文件：' + name)
shutil.copyfile(Path(__file__).with_name('serve.py'), WEB / 'serve.py')
shutil.copyfile(GAME / 'docs/web-build.md', WEB / '使用与部署.md')
for name in ['ASSET_LICENSES.md', 'THIRD_PARTY_NOTICES.md', 'LICENSE']:
    if (GAME / name).is_file(): shutil.copyfile(GAME / name, WEB / name)
(WEB / '本地试玩.cmd').write_text('@echo off\r\ncd /d "%~dp0"\r\nwhere py >nul 2>nul\r\nif %errorlevel%==0 (\r\n  py -3 serve.py\r\n) else (\r\n  python serve.py\r\n)\r\npause\r\n', encoding='ascii')
(WEB / '_headers').write_text('/*\n  Cross-Origin-Opener-Policy: same-origin\n  Cross-Origin-Embedder-Policy: require-corp\n  Cross-Origin-Resource-Policy: same-origin\n', encoding='utf-8')
(WEB / 'nginx-location.conf.example').write_text('''# 放入自己的 HTTPS server 中；root 改为解压目录。
location / {
    root /srv/minghe-web;
    index index.html;
    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;
    add_header Cross-Origin-Resource-Policy "same-origin" always;
    types {
        text/html html;
        application/javascript js;
        application/wasm wasm;
        image/png png;
    }
    default_type application/octet-stream;
    try_files $uri $uri/ =404;
}
''', encoding='utf-8')
dest = args.output or GAME / f'builds/冥河，冥河！v{version}-Web.zip'
dest.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(dest, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for path in sorted(WEB.iterdir()):
        if path.is_file(): archive.write(path, path.name)
print(str(dest), dest.stat().st_size, flush=True)
