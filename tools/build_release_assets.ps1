# 构建 Release 资产：按品牌整包 + 全量合集 + 机型索引 + SHA256 校验 + 发布说明
# 用法: pwsh tools/build_release_assets.ps1 -Tag v20261004 -UpstreamSha <sha> -UpstreamDate <yyyy-MM-dd> -Changed
param(
    [string]$Tag = ("v" + ([DateTime]::UtcNow.AddHours(8).ToString('yyyyMMdd'))),
    [string]$UpstreamSha = "",
    [string]$UpstreamDate = "",
    [string]$WorkflowRun = "",
    [string]$ChangesFile = "",
    [switch]$Changed
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Lf([string]$Path,[string]$Text){
    $t = $Text -replace "`r`n","`n"
    [IO.File]::WriteAllText($Path,$t,$utf8NoBom)
}

function New-ZipFromEntries([object[]]$Entries, [string]$ZipPath){
    $relList = New-Object 'System.Collections.Generic.List[string]'
    $map = @{}
    foreach($e in $Entries){
        $relList.Add($e.Name)
        $map[$e.Name] = $e.Path
    }
    $relList.Sort([StringComparer]::Ordinal)
    $ts = [DateTimeOffset]::new(2020,1,1,0,0,0,[TimeSpan]::Zero)
    $fs = [IO.File]::Open($ZipPath,[IO.FileMode]::Create)
    try{
        $zip = New-Object System.IO.Compression.ZipArchive($fs,[IO.Compression.ZipArchiveMode]::Create)
        try{
            foreach($name in $relList){
                $entry = $zip.CreateEntry($name,[IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = $ts
                $es = $entry.Open()
                try{
                    $bytes = [IO.File]::ReadAllBytes($map[$name])
                    $es.Write($bytes,0,$bytes.Length)
                } finally { $es.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $fs.Dispose() }
}

function Esc-Csv([string]$s){ if($null -eq $s){ return '' }; return $s.Replace('"','""') }

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$dist = Join-Path $root 'dist'
if(-not $dist.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)){ throw "dist 路径异常: $dist" }
if([IO.Directory]::Exists($dist)){ [IO.Directory]::Delete($dist, $true) }
[void][IO.Directory]::CreateDirectory($dist)

$infra = @('.github','tools','_upstream','dist','update')
# Release 资产文件名只能用 ASCII（GitHub 会替换非 ASCII 字符），品牌目录名映射为英文 slug
$brandSlug = @{
    '小米'='Xiaomi'; '红米'='Redmi'; '三星'='Samsung'; '华为'='Huawei'; '荣耀'='HONOR'
    '魅族'='Meizu'; '华硕'='ASUS'; '中兴'='ZTE'; '摩托罗拉'='Motorola'; '索尼'='Sony'
    '酷派'='Coolpad'; '智选'='Zhixuan'; '谷歌'='Google'; '努比亚'='Nubia'; '联想'='Lenovo'
    '一加'='OnePlus'; '诺基亚'='Nokia'; '黑鲨'='BlackShark'; '锤子'='Smartisan'; '乐视'='Letv'
}
function Get-BrandSlug([string]$n){
    if($brandSlug.ContainsKey($n)){ return $brandSlug[$n] }
    $s = ($n -replace '[^A-Za-z0-9._-]','-').Trim('-')
    if($s -eq ''){ $s = 'Brand' }
    return $s
}
$nameList = New-Object 'System.Collections.Generic.List[string]'
foreach($d in (Get-ChildItem -LiteralPath $root -Directory)){
    if($d.Name -in $infra -or $d.Name.StartsWith('.')){ continue }
    $nameList.Add($d.Name)
}
$nameList.Sort([StringComparer]::Ordinal)

$ver = $Tag
$pubDate = [DateTime]::UtcNow.AddHours(8).ToString('yyyy-MM-dd HH:mm')
$total = 0
$brandRows = New-Object System.Collections.Generic.List[object]
$allEntries = New-Object System.Collections.Generic.List[object]
$indexLines = New-Object System.Collections.Generic.List[string]
$indexLines.Add('"品牌","机型","代号","型号","文件夹","压缩包"')

foreach($bn in $nameList){
    $bdir = Join-Path $root $bn
    $zips = @(Get-ChildItem -LiteralPath $bdir -Recurse -File -Filter *.zip)
    if($zips.Count -eq 0){ continue }
    $entries = New-Object System.Collections.Generic.List[object]
    foreach($z in $zips){
        $rel = $z.FullName.Substring($bdir.Length + 1).Replace([char]92,'/')
        $entries.Add([pscustomobject]@{ Path = $z.FullName; Name = $rel })
        $allEntries.Add([pscustomobject]@{ Path = $z.FullName; Name = ($bn + '/' + $rel) })

        $segs = $rel.Split('/')
        $folderName = $segs[0]
        $zipName = $segs[$segs.Count - 1]
        $market = $folderName; $code = ''
        if($folderName -match '^(.*) \(([^()]+)\)(?: #\d+)?$'){ $market = $Matches[1]; $code = $Matches[2] }
        $model = ''
        if($zipName -match '^(.*) \(([^()]+)\)\.zip$'){ $model = $Matches[2] }
        $indexLines.Add(('"{0}","{1}","{2}","{3}","{4}","{5}"' -f (Esc-Csv $bn), (Esc-Csv $market), (Esc-Csv $code), (Esc-Csv $model), (Esc-Csv ($bn + '/' + $folderName)), (Esc-Csv $zipName)))
    }
    $assetName = ('Magisk-DeviceSpoofer_' + (Get-BrandSlug $bn) + '_' + $zips.Count + '_' + $ver + '.zip')
    New-ZipFromEntries $entries.ToArray() (Join-Path $dist $assetName)
    $total += $zips.Count
    $brandRows.Add([pscustomobject]@{ Name = $bn; Count = $zips.Count; Asset = $assetName })
    Write-Host ($bn + ': ' + $zips.Count + ' 个机型 -> ' + $assetName)
}

$fullName = ('Magisk-DeviceSpoofer_All_' + $total + '_' + $ver + '.zip')
New-ZipFromEntries $allEntries.ToArray() (Join-Path $dist $fullName)
$indexName = ('Magisk-DeviceSpoofer_Index_' + $total + '_' + $ver + '.csv')
Write-Lf (Join-Path $dist $indexName) (([string]::Join("`n", $indexLines)) + "`n")

# SHA256 校验和（zip + csv，名称排序保证可复现）
$sumNames = New-Object 'System.Collections.Generic.List[string]'
foreach($f in (Get-ChildItem -LiteralPath $dist -File)){
    if($f.Name -in @('release-notes.md','release-title.txt')){ continue }
    if($f.Name.StartsWith('SHA256SUMS_')){ continue }
    $sumNames.Add($f.Name)
}
$sumNames.Sort([StringComparer]::Ordinal)
$sumLines = New-Object System.Collections.Generic.List[string]
foreach($n in $sumNames){
    $h = (Get-FileHash -LiteralPath (Join-Path $dist $n) -Algorithm SHA256).Hash.ToLowerInvariant()
    $sumLines.Add($h + '  ' + $n)
}
$sumName = ('SHA256SUMS_' + $ver + '.txt')
Write-Lf (Join-Path $dist $sumName) (([string]::Join("`n", $sumLines)) + "`n")

# 变更摘要（优先读 CI 生成的 name-status 文件，本地回退到 git diff）
$changeLines = New-Object System.Collections.Generic.List[string]
$diffRaw = @()
if($Changed){
    if($ChangesFile -and (Test-Path -LiteralPath $ChangesFile)){
        $diffRaw = @(Get-Content -LiteralPath $ChangesFile)
    } elseif((Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath (Join-Path $root '.git'))){
        $diffRaw = @(& git -C $root diff --name-status --diff-filter=ADMR 'HEAD^' 'HEAD' -- '*.zip' 2>$null)
    }
    $add = 0; $del = 0; $mod = 0
    $disp = New-Object System.Collections.Generic.List[string]
    foreach($line in $diffRaw){
        if($line -notmatch "^([AMDR])\t(.+)$"){ continue }
        $st = $Matches[1]; $path = $Matches[2]
        if($path -notmatch '\.zip$'){ continue }
        $parts = $path.Split('/')
        $dispName = if($parts.Count -ge 2){ $parts[0] + ' / ' + $parts[1] } else { $path }
        if($st -eq 'A'){ $add++; $label = '新增' }
        elseif($st -eq 'D'){ $del++; $label = '移除' }
        else { $mod++; $label = '更新' }
        if($disp.Count -lt 40){ $disp.Add('- [' + $label + '] ' + $dispName) }
    }
    $changedTotal = $add + $mod + $del
    if($changedTotal -eq 0){
        $changeLines.Add('- 本次同步：机型数据无变化（仅更新上游版本记录）')
    } else {
        $changeLines.Add('- 本次同步：新增 ' + $add + ' 个 / 更新 ' + $mod + ' 个 / 移除 ' + $del + ' 个机型')
        if($disp.Count -gt 0){
            $changeLines.Add('')
            foreach($l in $disp){ $changeLines.Add($l) }
            if($changedTotal -gt $disp.Count){ $changeLines.Add('- …… 其余 ' + ($changedTotal - $disp.Count) + ' 个机型见提交记录') }
        }
    }
} else {
    $changeLines.Add('- 本版为手动触发的重建发布，模块内容与上一版一致')
}

if($UpstreamSha){
    $short = $UpstreamSha.Substring(0,[math]::Min(9,$UpstreamSha.Length))
    $shaLine = 'MobileModels@' + $short
    if($UpstreamDate){ $shaLine = $shaLine + '（' + $UpstreamDate + '）' }
} else {
    $shaLine = 'MobileModels 最新数据'
}
$fullMB = [math]::Round((Get-Item -LiteralPath (Join-Path $dist $fullName)).Length / 1MB, 1)

$notes = New-Object System.Collections.Generic.List[string]
$notes.Add('## 全机型机型伪装 Magisk 模块合集 ' + $Tag)
$notes.Add('')
$notes.Add('**' + $brandRows.Count + ' 个品牌 / ' + $total + ' 个机型**：每个机型一个独立可刷模块（Android 1 ~ 17 适配）；纯本地脚本，无联网、无上传。')
$notes.Add('')
$notes.Add('### 下载文件')
$notes.Add('| 文件 | 内容 |')
$notes.Add('| :--- | :--- |')
$notes.Add('| **' + $fullName + '**（' + $fullMB + ' MB） | 全量 ' + $total + ' 个机型，一次拿全 |')
$notes.Add('| **Magisk-DeviceSpoofer_品牌_数量_' + $ver + '.zip** × ' + $brandRows.Count + ' | 按品牌整包（英文品牌名，如 Xiaomi=小米 / Samsung=三星 / HONOR=荣耀；解压后到对应机型文件夹取 zip 刷入） |')
$notes.Add('| **' + $indexName + '** | 机型索引：品牌 / 机型 / 代号 / 型号 / 包内路径 |')
$notes.Add('| **' + $sumName + '** | SHA256 校验和 |')
$notes.Add('')
$notes.Add('### 本版要点')
$notes.Add('- 数据版本：' + $shaLine)
$notes.Add('- 发布时间：' + $pubDate + '（北京时间）')
foreach($l in $changeLines){ $notes.Add($l) }
$notes.Add('')
$notes.Add('### 使用')
$notes.Add('1. 下载对应品牌整包（或全量合集）并解压；')
$notes.Add('2. 找到目标机型文件夹，把里面的模块 zip 用 Magisk / KernelSU / APatch 管理器刷入，重启生效；')
$notes.Add('3. Android 2.2-5.x 用 recovery 直接刷同一 zip；Android 1.x-5.x 见模块内 legacy/ 脚本；')
$notes.Add('4. 校验下载：sha256sum -c ' + $sumName + '（Windows 可用 certutil -hashfile 逐个核对）。')
$notes.Add('')
$notes.Add('### 说明')
$notes.Add('- 模块内置更新信息（updateJson）：刷入后可在 Magisk / KernelSU / APatch 管理器内直接检查并更新。')
$notes.Add('- 安装完成后模块会自动打开作者的酷安主页（装有酷安 App 直接跳转，未安装则用浏览器打开）；KernelSU / APatch 可用模块「执行」按钮再次打开。')
$notes.Add('- 数据来源：KHwang9883/MobileModels（CC BY-NC-SA 4.0），本仓库免费分享、无任何商业用途；')
$notes.Add('- 单个机型 zip 也可以直接在仓库目录树中下载：https://github.com/L0NE-6/Magisk-DeviceSpoofer')
if($WorkflowRun){
    $notes.Add('- 本 Release 由 GitHub Actions 自动构建发布：[工作流运行记录](' + $WorkflowRun + ')')
} else {
    $notes.Add('- 本 Release 由 GitHub Actions 自动构建发布。')
}
Write-Lf (Join-Path $dist 'release-notes.md') ([string]::Join("`n", $notes))

$title = ('全机型机型伪装 Magisk 模块合集 ' + $Tag + ' · ' + $brandRows.Count + ' 品牌 / ' + $total + ' 机型 · Android 1-17')
Write-Lf (Join-Path $dist 'release-title.txt') ($title + "`n")

if($env:GITHUB_OUTPUT){
    ('tag=' + $Tag) | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
}
Write-Host ('发布资产构建完成: ' + $dist)
Write-Host ('汇总: ' + $brandRows.Count + ' 品牌 / ' + $total + ' 机型; 全量包 ' + $fullMB + ' MB')
