param(
    [Parameter(Mandatory=$true)][string]$PythonExe,
    [Parameter(Mandatory=$true)][string]$GodotExe,
    [switch]$InstallDependencies
)
# 仅制作写谱器。下载和安装发生在开发机，谱师运行时全部使用随包文件。
$ErrorActionPreference = 'Stop'
$rhythmRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $rhythmRoot
try {
    New-Item -ItemType Directory -Force builds/rhythm-models | Out-Null
    New-Item -ItemType File -Force builds/.gdignore | Out-Null
    if ($InstallDependencies) {
        & $PythonExe -m venv builds/rhythm-venv
        if ($LASTEXITCODE -ne 0) { throw '创建 Python 环境失败' }
    }
    $rhythmPython = Join-Path $rhythmRoot 'builds/rhythm-venv/Scripts/python.exe'
    if ($InstallDependencies) {
        & $rhythmPython -m pip install --extra-index-url https://download.pytorch.org/whl/cpu -r tools/rhythm_analyzer/requirements-lock.txt
        if ($LASTEXITCODE -ne 0) { throw '安装识别器依赖失败' }
    }
    if (-not (Test-Path builds/rhythm-models/final0.ckpt)) {
        Invoke-WebRequest 'https://cloud.cp.jku.at/public.php/dav/files/7ik4RrBKTS273gp/final0.ckpt' -OutFile builds/rhythm-models/final0.ckpt
    }
    & $rhythmPython -m unittest discover -s tools/rhythm_analyzer -p test_analysis.py
    if ($LASTEXITCODE -ne 0) { throw '节奏拟合测试失败' }
    & $rhythmPython -m PyInstaller --noconfirm --onedir --name rhythm_analyzer --distpath builds/chart-studio --workpath builds/rhythm-pyinstaller --specpath builds/rhythm-pyinstaller --collect-all beat_this --collect-all rotary_embedding_torch --collect-all soxr tools/rhythm_analyzer/analyze.py
    if ($LASTEXITCODE -ne 0) { throw '识别器打包失败' }
    New-Item -ItemType Directory -Force builds/chart-studio/rhythm_analyzer/models | Out-Null
    Copy-Item -LiteralPath builds/rhythm-models/final0.ckpt -Destination builds/chart-studio/rhythm_analyzer/models/final0.ckpt
    & $GodotExe --headless --path . --export-release 'Chart Studio Windows' builds/chart-studio/minghe-chart-studio.exe
    if ($LASTEXITCODE -ne 0) { throw '写谱器导出失败' }
    & $rhythmPython tools/rhythm_analyzer/package.py
    if ($LASTEXITCODE -ne 0) { throw '开发包打包失败' }
} finally { Pop-Location }
