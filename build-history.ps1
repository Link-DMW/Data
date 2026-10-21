# ============================================================
# 从 git 历史重建 history.json（页面「历史数据」用的每日快照库）
# 每次提交的 index.html 里都有完整数据，按 reportDate 去重，同日以最后一次提交为准
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File build-history.ps1
#       可选参数 -RepoPath D:\HTML  -OutFile D:\HTML\history.json
# ============================================================
param(
    [string]$RepoPath = 'D:\HTML',
    [string]$OutFile  = 'D:\HTML\history.json'
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (-not (Test-Path (Join-Path $RepoPath '.git'))) { throw "不是 git 仓库: $RepoPath" }

# 字段约定（页面里按此顺序读取）
#   p: [店铺名, 支付金额, 订单数, 访客数]           —— POP
#   f: [店铺名, 访客数, 昨日销量, 7日销量]          —— 全托管
$revRe = 'var reportDate\s*=\s*"([^"]*)"'
$popRe = '(?s)var popData = \[(.*?)\];'
$fulRe = '(?s)var fullData = \[(.*?)\];'

$byDate = [ordered]@{}
$commits = & git -C $RepoPath log --reverse --format='%H' -- index.html
if (-not $commits) { throw '读不到 git 历史' }

$ok = 0; $skip = 0
foreach ($sha in $commits) {
    $spec = "{0}:index.html" -f $sha
    $html = & git -C $RepoPath show $spec 2>$null
    if (-not $html) { $skip++; continue }
    $html = ($html -join "`n")

    $d = [regex]::Match($html, $revRe).Groups[1].Value
    $pm = [regex]::Match($html, $popRe)
    $fm = [regex]::Match($html, $fulRe)
    if (-not $d -or -not $pm.Success -or -not $fm.Success) { $skip++; continue }

    try {
        $pop  = ('[' + $pm.Groups[1].Value + ']') | ConvertFrom-Json
        $full = ('[' + $fm.Groups[1].Value + ']') | ConvertFrom-Json
    } catch { $skip++; continue }
    if (-not $pop -or $pop.Count -lt 5) { $skip++; continue }

    $p = @()
    foreach ($s in $pop) {
        $pay = $null; if ($null -ne $s.pay) { $pay = [math]::Round([double]$s.pay, 2) }
        $ord = $null; if ($null -ne $s.orders) { $ord = [int]$s.orders }
        $vis = $null; if ($null -ne $s.visitors) { $vis = [int]$s.visitors }
        $p += ,@($s.store, $pay, $ord, $vis)
    }
    $f = @()
    foreach ($s in $full) {
        $vis = $null; if ($null -ne $s.visitors) { $vis = [int]$s.visitors }
        $sy  = $null; if ($null -ne $s.salesYest) { $sy = [int]$s.salesYest }
        $s7  = $null; if ($null -ne $s.sales7d) { $s7 = [int]$s.sales7d }
        $f += ,@($s.store, $vis, $sy, $s7)
    }
    $byDate[$d] = [ordered]@{ d = $d; p = $p; f = $f }
    $ok++
}

$days = @()
foreach ($k in ($byDate.Keys | Sort-Object)) { $days += ,$byDate[$k] }
$obj = [ordered]@{
    generated = (Get-Date -Format 'yyyy-MM-dd HH:mm')
    source    = 'git:index.html daily snapshots'
    fields    = [ordered]@{ p = 'store,pay,orders,visitors'; f = 'store,visitors,salesYest,sales7d' }
    days      = $days
}
$json = $obj | ConvertTo-Json -Depth 8 -Compress
[System.IO.File]::WriteAllText($OutFile, $json, (New-Object System.Text.UTF8Encoding($false)))

"提交数=$($commits.Count)  解析成功=$ok  跳过=$skip  不同日期=$($days.Count)"
"日期范围: $($days[0].d) ~ $($days[-1].d)"
"输出: $OutFile  $([math]::Round((Get-Item $OutFile).Length / 1KB, 1)) KB"
