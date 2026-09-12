param(
    [Parameter(Mandatory = $true)][string]$GodotExe,
    [int]$TimeoutSeconds = 60
)
# 每个测试独立进程；检查完成标记和错误日志，避免解析失败后误把 quit-after 的 0 当成功。
$ErrorActionPreference = 'Stop'
$studioProjectPath = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$studioLogDirectory = Join-Path $studioProjectPath 'builds/test-results'
New-Item -ItemType Directory -Force $studioLogDirectory | Out-Null
$studioSuites = @{
    'run_local_chart_tests' = 'LOCAL CHART TESTS: 0'
    'run_trial_launcher_tests' = 'TRIAL LAUNCHER TESTS: 0'
    'run_trial_flow_tests' = 'TRIAL FLOW TESTS: 0'
    'run_background_input_tests' = 'BACKGROUND INPUT TESTS: 0'
    'run_studio_tests' = 'STUDIO TESTS: 0'
    'run_scene_binding_tests' = 'SCENE BINDING TESTS: 0'
    'run_alignment_tests' = 'ALIGNMENT TESTS: 0'
    'run_input_tests' = 'INPUT TESTS: 0'
    'run_workspace_smoke' = 'WORKSPACE SMOKE COMPLETE'
    'run_ui_tests' = 'UI TESTS: 0'
    'run_stability_tests' = 'STABILITY TESTS: 0'
    'run_layout_tests' = 'LAYOUT TESTS: 0'
    'run_open_dialog_tests' = 'OPEN DIALOG TESTS: 0'
    'run_rhythm_tests' = 'RHYTHM TESTS: 0'
    'run_touchpad_tests' = 'TOUCHPAD TESTS: 0'
    'run_compact_tracks_tests' = 'COMPACT TRACK TESTS: 0'
    'run_cue_tests' = 'CUE TESTS: 0'
    'run_rhythm_fit_tests' = 'RHYTHM FIT TESTS: 0'
    'run_tuning_authoring_tests' = 'TUNING_AUTHORING: 0 failures'
    'run_tuning_ui_tests' = 'TUNING UI TESTS: 0'
    'run_tuning_boundaries_tests' = 'TUNING BOUNDARY TESTS: 0'
    'run_preview_frame_tests' = 'PREVIEW FRAME TESTS: 0'
    'run_preview_loading_tests' = 'PREVIEW LOADING TESTS: 0'
    'run_ghost_visibility_tests' = 'GHOST VISIBILITY TESTS: 0'
    'measure_preview_seek' = 'SEEK EQUIVALENCE: 0'
    'run_tuning_delivery_tests' = 'TUNING DELIVERY TESTS: 0'
}
foreach ($studioSuite in $studioSuites.Keys) {
    $studioStdoutPath = Join-Path $studioLogDirectory ($studioSuite + '.log')
    $studioStderrPath = Join-Path $studioLogDirectory ($studioSuite + '.error.log')
    $studioArguments = '--headless --path "{0}" --script res://tests/editor/{1}.gd --quit-after 600 -- --chart-editor' -f $studioProjectPath, $studioSuite
    if ($studioSuite -eq 'run_trial_flow_tests') { $studioArguments = $studioArguments.Replace('--quit-after 600 -- --chart-editor', '--quit-after 6000 -- --play-chart builds/trial-flow-input.zip --difficulty normal') }
    if ($studioSuite -eq 'measure_preview_seek') { $studioArguments += ' --quick' }
    $studioProcess = Start-Process -FilePath $GodotExe -ArgumentList $studioArguments -WorkingDirectory $studioProjectPath -WindowStyle Hidden -PassThru -RedirectStandardOutput $studioStdoutPath -RedirectStandardError $studioStderrPath
    if (-not $studioProcess.WaitForExit($TimeoutSeconds * 1000)) {
        # Godot 的 Windows console 包装器会启动实际引擎，只终止本次测试的进程树。
        Get-CimInstance Win32_Process -Filter "ParentProcessId = $($studioProcess.Id)" | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
        Stop-Process -Id $studioProcess.Id -ErrorAction SilentlyContinue
        throw "$studioSuite 超时；日志：$studioStdoutPath"
    }
    $studioProcess.Refresh()
    $studioOutput = [IO.File]::ReadAllText($studioStdoutPath) + [IO.File]::ReadAllText($studioStderrPath)
    if ($studioProcess.ExitCode -ne 0 -or -not $studioOutput.Contains($studioSuites[$studioSuite]) -or $studioOutput -match 'SCRIPT ERROR:|(?m)^ERROR:') {
        Write-Output $studioOutput
        throw "$studioSuite 未通过"
    }
    Write-Output "$studioSuite 通过"
}
