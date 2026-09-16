$ErrorActionPreference = 'Stop'
$cleanupRoot = [IO.Path]::GetFullPath('E:\大学\MEMO\编钟音游')
$auditDir = Join-Path $cleanupRoot 'Game/outputs/cleanup-20260916'
$manifest = Get-Content -LiteralPath (Join-Path $auditDir 'manifest.json') -Raw | ConvertFrom-Json
if (!(Test-Path -LiteralPath (Join-Path $auditDir 'protected-before.json'))) { throw '保留文件校验尚未完成' }
if (!(Test-Path -LiteralPath (Join-Path $auditDir 'document-edits.json'))) { throw '文档整理尚未完成' }
if (Test-Path -LiteralPath (Join-Path $auditDir 'recycle-results.jsonl')) { throw '已有执行记录，禁止盲目重跑' }
Add-Type -Path (Join-Path $auditDir 'RecycleOnly.cs')

# 再核对绝对边界和目录链接；不跟随 junction，不调用递归删除命令。
function Assert-OrdinaryTree([string]$path) {
 $item = Get-Item -LiteralPath $path -Force
 if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "清单内出现目录链接：$path" }
 if ($item.PSIsContainer) {
  foreach ($child in Get-ChildItem -LiteralPath $path -Force) { Assert-OrdinaryTree $child.FullName }
 }
}
foreach ($entry in $manifest.entries) {
 $full = [IO.Path]::GetFullPath($entry.path)
 if (!$full.StartsWith($cleanupRoot + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "越界路径：$full" }
 if ($full.StartsWith($auditDir,[StringComparison]::OrdinalIgnoreCase)) { throw '清单包含记录目录' }
 Assert-OrdinaryTree $full
}
$done=0
foreach ($entry in $manifest.entries) {
 $result = [RecycleOnly]::Send($entry.path)
 [ordered]@{path=$entry.path;result=$result;files=$entry.files;bytes=$entry.bytes;time=(Get-Date).ToString('o')} |
  ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $auditDir 'recycle-results.jsonl') -Encoding utf8
 $done++
 if ($done % 25 -eq 0 -or $result -ne '已回收') { Write-Output "$done / $($manifest.entries.Count) : $result" }
 # 出错保留当前项并停止批次，供复查；绝不改用强制删除。
 if ($result -ne '已回收') { throw "已停止：$($entry.path)；$result" }
}
Write-Output "完成 $done 项"
