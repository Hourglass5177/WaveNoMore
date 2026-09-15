param([string]$Godot = 'F:/godot 4.7.2/Godot_v4.7.2-stable_win64_console.exe',
    [string[]]$Suites = @('art','navigation','display','editor-font'))
# 临时覆盖只属于当前 worktree，验证不读写玩家配置。
$uiRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$overridePath = Join-Path $uiRoot 'override.cfg'
$previousOverride = if (Test-Path -LiteralPath $overridePath) { [IO.File]::ReadAllBytes($overridePath) } else { $null }
$reviewDir = Join-Path $uiRoot 'builds/ui-review'
New-Item -ItemType Directory -Force -Path $reviewDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $uiRoot 'builds/title-review') | Out-Null
# UI 会话使用确定的默认规则，不读取队友正在调整的策划表。
[IO.File]::WriteAllText((Join-Path $reviewDir 'default-planning.json'),'{"values":{}}')
try {
    $configuration = @'
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="WaveNoMore-UIReview"
'@
    [IO.File]::WriteAllText($overridePath,$configuration)
    $jobs = @(
        @{name='credits';script='res://tests/ui/run_credits_ui_tests.gd';args=' -- --planning-values=res://builds/ui-review/default-planning.json'},
        @{name='judgment-art';script='res://tests/visual/run_judgment_art_review.gd';args=' -- --chart-editor --planning-values=res://builds/ui-review/default-planning.json'},
        @{name='launch-guides';script='res://tools/ui/capture_launch_guides.gd';args=' -- --chart-editor --planning-values=res://builds/ui-review/default-planning.json'},
        @{name='pet-rules';script='res://tests/integration/pets/run_pet_tests.gd';args=' -- --planning-values=res://builds/ui-review/default-planning.json'},
        @{name='save';script='res://tests/integration/save/run_save_tests.gd';args=' -- --planning-values=res://builds/ui-review/default-planning.json'},
        @{name='result';script='res://tests/ui/run_result_ui_tests.gd';args=' -- --planning-values=res://builds/ui-review/default-planning.json'},
        @{name='clear-mark';script='res://tests/visual/capture_clear_mark_glow.gd';args=' -- --planning-values=res://builds/ui-review/default-planning.json'},
        @{name='stick-ingame';script='res://tests/visual/capture_stick_ingame.gd';args=' -- --planning-values=res://builds/ui-review/default-planning.json'},
        @{name='stick-motion';script='res://tests/visual/capture_stick_gesture.gd';args=' -- --chart-editor --planning-values=res://builds/ui-review/default-planning.json'},
        @{name='title-video';script='res://tests/visual/capture_title_transition.gd';args=' --write-movie builds/title-review/title-transition.avi --fixed-fps 60 --resolution 1280x720'},
        @{name='controller';script='res://tests/ui/run_controller_ui_tests.gd';args=' -- --planning-values=res://builds/ui-review/default-planning.json'},
        @{name='app-flow';script='res://tests/integration/app_flow/run_app_flow_smoke.gd';args=' -- --planning-values=res://builds/ui-review/default-planning.json'},
        @{name='title';script='res://tests/ui/run_title_ui_tests.gd';args=' -- --planning-values=res://builds/ui-review/default-planning.json'},
        @{name='art';script='res://tests/ui/run_art_ui_tests.gd';args=' -- --chart-editor --planning-values=res://builds/ui-review/default-planning.json'},
        @{name='carousel';script='res://tests/visual/run_level_carousel_tests.gd';args=''},
        @{name='navigation';script='res://tests/integration/pets/run_menu_navigation_tests.gd';args=''},
        @{name='display';script='res://tests/ui/run_display_font_tests.gd';args=''},
        @{name='editor-font';script='res://tests/ui/run_display_font_tests.gd';args=' -- --chart-editor'}
    )
    foreach ($job in $jobs) {
        if ($job.name -notin $Suites) { continue }
        $stdout = Join-Path $reviewDir ($job.name+'.log')
        $stderr = Join-Path $reviewDir ($job.name+'-errors.log')
        $arguments = '--path . --script '+$job.script+' --rendering-method gl_compatibility --max-fps 60 --quit-after 4000'+$job.args
        $process = Start-Process -FilePath $Godot -ArgumentList $arguments -WorkingDirectory $uiRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $process.WaitForExit()
        if ($process.ExitCode -ne 0 -or (Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR|ERROR:' -Quiet)) { throw "UI review failed: $($job.name); see $stderr" }
        Get-Content -LiteralPath $stdout | Select-Object -Last 1
    }
} finally {
    if ($null -ne $previousOverride) { [IO.File]::WriteAllBytes($overridePath,$previousOverride) }
    else { Remove-Item -LiteralPath $overridePath }
}
