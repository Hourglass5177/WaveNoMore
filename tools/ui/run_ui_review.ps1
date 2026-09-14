param([string]$Godot = 'F:/godot 4.7.2/Godot_v4.7.2-stable_win64_console.exe',
    [string[]]$Suites = @('art','navigation','display','editor-font'))
# 临时覆盖只属于当前 worktree，验证不读写玩家配置。
$uiRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$overridePath = Join-Path $uiRoot 'override.cfg'
$previousOverride = if (Test-Path -LiteralPath $overridePath) { [IO.File]::ReadAllBytes($overridePath) } else { $null }
$reviewDir = Join-Path $uiRoot 'builds/ui-review'
New-Item -ItemType Directory -Force -Path $reviewDir | Out-Null
try {
    $configuration = @'
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="WaveNoMore-UIReview"
'@
    [IO.File]::WriteAllText($overridePath,$configuration)
    $jobs = @(
        @{name='art';script='res://tests/ui/run_art_ui_tests.gd';args=' -- --chart-editor'},
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
