# 与上游 MobileModels 同步并重新生成全部机型模块
# 用法: pwsh tools/sync_from_upstream.ps1 -UpstreamDir ./_upstream [-Force]
#   - 先对比 brands/*.md 指纹；未变化则跳过（除非 -Force）
#   - 变化时调用 generate_all_brand_modules.ps1 全量重建（-Clean 清理上游已删除的机型）
#   - 更新 README.md 品牌统计块与 .github/upstream-fingerprint.txt
param(
    [string]$UpstreamDir = "$PSScriptRoot/../_upstream",
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Lf([string]$Path,[string]$Text){
    $t = $Text -replace "`r`n","`n"
    [IO.File]::WriteAllText($Path,$t,$utf8NoBom)
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$brandsDir = Join-Path (Resolve-Path -LiteralPath $UpstreamDir).Path 'brands'
if(-not (Test-Path -LiteralPath $brandsDir)){ throw "找不到上游 brands 目录: $brandsDir" }
$fpFile = Join-Path $root '.github/upstream-fingerprint.txt'

function Get-BrandsFingerprint([string]$Dir){
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $files = New-Object 'System.Collections.Generic.List[string]'
        foreach($f in (Get-ChildItem -LiteralPath $Dir -File -Filter *.md)){ $files.Add($f.Name) }
        $files.Sort([StringComparer]::Ordinal)
        $sb = New-Object System.Text.StringBuilder
        foreach($n in $files){
            $bytes = [IO.File]::ReadAllBytes((Join-Path $Dir $n))
            $h = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()
            [void]$sb.Append($n).Append(':').Append($h).Append("`n")
        }
        $final = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($sb.ToString()))
        return [BitConverter]::ToString($final).Replace('-','').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

$fingerprint = Get-BrandsFingerprint $brandsDir
$oldFingerprint = ''
if(Test-Path -LiteralPath $fpFile){ $oldFingerprint = (Get-Content -LiteralPath $fpFile -Raw).Trim() }
if(($fingerprint -eq $oldFingerprint) -and (-not $Force)){
    Write-Host ("上游 brands 数据未变化 (fingerprint: " + $fingerprint + ")，跳过生成。")
    exit 0
}
Write-Host ("同步开始: upstream fingerprint " + $fingerprint)

# 品牌目录 = 仓库根目录下除基础设施外的目录
$infra = @('.github','tools','_upstream','update','assets')
function Get-BrandDirs { Get-ChildItem -LiteralPath $root -Directory | Where-Object { $_.Name -notin $infra -and -not $_.Name.StartsWith('.') } }
function Count-Zips([object[]]$Dirs){ $n = 0; foreach($d in $Dirs){ if($d){ $n += @(Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Filter *.zip).Count } }; return $n }

$before = Count-Zips @(Get-BrandDirs)
Write-Host ("生成前 zip 数量: " + $before)

& (Join-Path $PSScriptRoot 'generate_all_brand_modules.ps1') -BrandsDir $brandsDir -OutRoot $root -ZipOnly -Clean -NoMeta

$after = Count-Zips @(Get-BrandDirs)
Write-Host ("生成后 zip 数量: " + $after)

# 安全阀：数量异常下降时中止，避免把误删内容提交上去
if($after -le 0){ throw "生成结果为空，中止（不提交）" }
if($before -gt 0 -and $after -lt [math]::Floor($before * 0.8)){ throw ("生成数量异常下降: " + $before + " -> " + $after + "，中止（不提交）") }

# 为每个模块写入管理器更新信息（updateJson / version / versionCode）
& (Join-Path $PSScriptRoot 'apply_update_metadata.ps1') -Root $root

# 更新 README.md 品牌统计块
$readmePath = Join-Path $root 'README.md'
$begin = '<!-- BRAND_STATS:BEGIN -->'
$end = '<!-- BRAND_STATS:END -->'
$readme = [IO.File]::ReadAllText($readmePath)
$pattern = [regex]::Escape($begin) + '[\s\S]*?' + [regex]::Escape($end)
$m = [regex]::Match($readme, $pattern)
if(-not $m.Success){ throw ("README.md 缺少 " + $begin + " / " + $end + " 标记") }

$stats = @(Get-BrandDirs | ForEach-Object {
    [pscustomobject]@{
        Name  = $_.Name
        Count = @(Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Filter *.zip).Count
    }
})
$sorted = @($stats | Sort-Object -Property @{Expression={$_.Count};Descending=$true}, @{Expression={$_.Name};Descending=$false})
$half = [int][math]::Ceiling($sorted.Count / 2)
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('| 品牌 | 数量 | 品牌 | 数量 |')
$lines.Add('| :--- | ---: | :--- | ---: |')
for($i = 0; $i -lt $half; $i++){
    $left = $sorted[$i]
    if(($i + $half) -lt $sorted.Count){
        $right = $sorted[$i + $half]
        $lines.Add('| ' + $left.Name + ' | ' + $left.Count + ' | ' + $right.Name + ' | ' + $right.Count + ' |')
    } else {
        $lines.Add('| ' + $left.Name + ' | ' + $left.Count + ' | | |')
    }
}
$total = ($sorted | Measure-Object Count -Sum).Sum
$lines.Add('')
$lines.Add('**合计：' + $total + ' 个机型 / ' + $sorted.Count + ' 个品牌**')
$block = $begin + "`n`n" + ([string]::Join("`n", $lines)) + "`n`n" + $end
$newReadme = $readme.Substring(0, $m.Index) + $block + $readme.Substring($m.Index + $m.Length)
Write-Lf $readmePath $newReadme
Write-Host ("README 统计已更新: " + $total + " 个机型 / " + $sorted.Count + " 个品牌")

Write-Lf $fpFile ($fingerprint + "`n")
Write-Host ("同步完成: " + $fingerprint)

if(Get-Command git -ErrorAction SilentlyContinue){
    $changed = @(& git -C $root status --porcelain)
    Write-Host ("git 变更条目数: " + $changed.Count)
}
