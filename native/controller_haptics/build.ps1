param(
	[switch]$PrepareDependencies,
	[string]$Python = 'python',
	[string]$CompilerBin = '',
	[int]$Jobs = 4
)
$ErrorActionPreference = 'Stop'
$hapticsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$hapticsDeps = Join-Path $hapticsRoot '.godot/haptics_deps'
$hapticsTools = Join-Path $hapticsRoot '.godot/haptics_build_tools'
if ($PrepareDependencies) {
	# Versions intentionally pinned; no system installation or global Git/Python configuration.
	if (-not (Test-Path -LiteralPath (Join-Path $hapticsDeps 'godot-cpp'))) {
		& git clone --depth 1 --branch godot-4.5-stable https://github.com/godotengine/godot-cpp.git (Join-Path $hapticsDeps 'godot-cpp')
		if ($LASTEXITCODE -ne 0) { throw 'godot-cpp download failed' }
	}
	if (-not (Test-Path -LiteralPath (Join-Path $hapticsDeps 'SDL'))) {
		& git clone --depth 1 --branch release-3.4.16 https://github.com/libsdl-org/SDL.git (Join-Path $hapticsDeps 'SDL')
		if ($LASTEXITCODE -ne 0) { throw 'SDL download failed' }
	}
	if (-not (Test-Path -LiteralPath (Join-Path $hapticsTools 'cmake/data/bin/cmake.exe'))) {
		& $Python -m pip install --disable-pip-version-check --index-url https://pypi.org/simple --target $hapticsTools cmake==4.1.0 ninja==1.13.0
		if ($LASTEXITCODE -ne 0) { throw 'Project-local build tools download failed' }
	}
}
$hapticsCmake = Join-Path $hapticsTools 'cmake/data/bin/cmake.exe'
$hapticsNinja = Join-Path $hapticsTools 'bin/ninja.exe'
if (-not $CompilerBin) { $CompilerBin = Split-Path (Get-Command clang++.exe).Source }
$hapticsBuild = Join-Path $hapticsRoot '.godot/haptics_build'
$hapticsPython = (Get-Command $Python).Source
& $hapticsCmake -S $PSScriptRoot -B $hapticsBuild -G Ninja `
	"-DCMAKE_MAKE_PROGRAM=$hapticsNinja" "-DCMAKE_BUILD_TYPE=Release" `
	"-DCMAKE_C_COMPILER=$CompilerBin/clang.exe" "-DCMAKE_CXX_COMPILER=$CompilerBin/clang++.exe" `
	"-DPython3_EXECUTABLE=$hapticsPython"
if ($LASTEXITCODE -ne 0) { throw 'CMake configuration failed' }
& $hapticsCmake --build $hapticsBuild --target wnm_controller_haptics --parallel $Jobs
if ($LASTEXITCODE -ne 0) { throw 'Native compilation failed' }
