$ErrorActionPreference = 'Stop'
$cleanupRoot = [IO.Path]::GetFullPath('E:\大学\MEMO\编钟音游')
$auditDir = Join-Path $cleanupRoot 'Game/outputs/cleanup-20260916'
$logPath = Join-Path $auditDir 'recycle-results.jsonl'
$manifest = Get-Content -LiteralPath (Join-Path $auditDir 'manifest.json') -Raw | ConvertFrom-Json
$previous = @(Get-Content -LiteralPath $logPath | ForEach-Object { $_ | ConvertFrom-Json })
$completed = @{}
foreach ($r in $previous) { if ($r.result -eq '已回收') { $completed[$r.path] = $true } }
$key = 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Explorer/BitBucket/Volume/{c2808ab5-011a-4bfa-9f18-47f6b6c71af6}'
if ((Get-ItemProperty -LiteralPath $key).MaxCapacity -lt 102400) { throw '回收站尚未扩容到用户允许的 100 GiB' }
$recycleDir = 'E:\$Recycle.Bin\S-1-5-21-1942464140-2856953516-1393776520-1001'
Add-Type -Path (Join-Path $auditDir 'RecycleOnly.cs')

function Get-RecycleReceipts {
 $receipts = @{}
 foreach ($item in Get-ChildItem -LiteralPath $recycleDir -Filter '$I*' -Force) {
  # Shell 刚写入的回收元数据可能仍持有句柄，允许共享读写并短暂等待。
  $stream = [IO.File]::Open($item.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
  try { $memory = [IO.MemoryStream]::new(); $stream.CopyTo($memory); $b = $memory.ToArray() } finally { $stream.Dispose(); if ($memory) { $memory.Dispose() } }
  $version = [BitConverter]::ToInt64($b,0)
  if ($version -eq 2) {
   $length = [BitConverter]::ToInt32($b,24)
   $original = [Text.Encoding]::Unicode.GetString($b,28,$length*2).TrimEnd([char]0)
  } elseif ($version -eq 1) {
   $original = [Text.Encoding]::Unicode.GetString($b,24,$b.Length-24).TrimEnd([char]0)
  } else { continue }
  $payload = Join-Path $recycleDir ('$R' + $item.Name.Substring(2))
  if (Test-Path -LiteralPath $payload) { $receipts[$original] = $item.FullName }
 }
 return $receipts
}
function Assert-OrdinaryTree([string]$path) {
 $full = [IO.Path]::GetFullPath($path)
 if (!$full.StartsWith($cleanupRoot+'\',[StringComparison]::OrdinalIgnoreCase)) { throw "越界路径 $full" }
 $item = Get-Item -LiteralPath $full -Force
 if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "不处理目录链接 $full" }
 if ($item.PSIsContainer) { foreach ($child in Get-ChildItem -LiteralPath $full -Force) { Assert-OrdinaryTree $child.FullName } }
}
$receipts = Get-RecycleReceipts
# 保存续跑前仍存在的全部回收记录，包括本次项目之外的旧回收项。
$receiptFiles = @($receipts.Values)
$receipts | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $auditDir 'receipts-before-resume.json') -Encoding utf8
$done=0
foreach ($entry in $manifest.entries) {
 if ($completed.ContainsKey($entry.path)) { continue }
 if (!(Test-Path -LiteralPath $entry.path) -and $receipts.ContainsKey($entry.path)) {
  [ordered]@{path=$entry.path;result='已回收';files=$entry.files;bytes=$entry.bytes;time=(Get-Date).ToString('o');resumed=$true;receipt_recovered=$true} |
   ConvertTo-Json -Compress | Add-Content -LiteralPath $logPath -Encoding utf8
  continue
 }
 Assert-OrdinaryTree $entry.path
 $result = [RecycleOnly]::Send($entry.path)
 $after = Get-RecycleReceipts
 [ordered]@{path=$entry.path;result=$result;files=$entry.files;bytes=$entry.bytes;time=(Get-Date).ToString('o');resumed=$true} |
  ConvertTo-Json -Compress | Add-Content -LiteralPath $logPath -Encoding utf8
 if ($result -ne '已回收') { throw "停止：$($entry.path)；$result" }
 if (!$after.ContainsKey($entry.path)) { throw "停止：找不到新回收项 $($entry.path)" }
 foreach ($old in $receiptFiles) { if (!(Test-Path -LiteralPath $old)) { throw "停止：旧回收记录消失 $old" } }
 $receiptFiles += $after[$entry.path]
 $done++
 if ($done % 20 -eq 0) { Write-Output "续跑 $done 项，每项回收记录核对通过" }
}
Write-Output "续跑完成 $done 项"
