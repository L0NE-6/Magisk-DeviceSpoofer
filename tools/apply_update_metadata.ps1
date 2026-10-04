# 为每个机型模块写入管理器更新信息（updateJson / version / versionCode）
# - 清单 update/versions.tsv 记录每个模块的版本号与内容指纹
# - 只有模块内容真的变化时才提升版本号；未变化模块保持字节不变（不产生 git diff）
# - 生成 update/<模块id>.json：Magisk / KernelSU / APatch 据此检查更新
param(
    [string]$Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path,
    [string]$Repo = 'L0NE-6/Magisk-DeviceSpoofer',
    [string]$Branch = 'main',
    [int]$LegacyVersionCode = 2026100402
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$rawBase = 'https://raw.githubusercontent.com/' + $Repo + '/' + $Branch + '/'

function Write-Lf([string]$Path,[string]$Text){
    $t = $Text -replace "`r`n","`n"
    [IO.File]::WriteAllText($Path,$t,$utf8NoBom)
}

function Get-TextBytes([string]$s){ return [Text.Encoding]::UTF8.GetBytes($s) }

function Get-HashHex([byte[]]$bytes){
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function New-ZipFromEntryData([object[]]$Entries, [string]$ZipPath){
    $names = New-Object 'System.Collections.Generic.List[string]'
    $map = @{}
    foreach($e in $Entries){ $names.Add($e.Name); $map[$e.Name] = $e.Bytes }
    $names.Sort([StringComparer]::Ordinal)
    $ts = [DateTimeOffset]::new(2020,1,1,0,0,0,[TimeSpan]::Zero)
    $fs = [IO.File]::Open($ZipPath,[IO.FileMode]::Create)
    try{
        $zip = New-Object System.IO.Compression.ZipArchive($fs,[IO.Compression.ZipArchiveMode]::Create)
        try{
            foreach($n in $names){
                $entry = $zip.CreateEntry($n,[IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = $ts
                $es = $entry.Open()
                try{ $b = $map[$n]; $es.Write($b,0,$b.Length) } finally { $es.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $fs.Dispose() }
}

# 读取旧清单（模块 id -> 版本号/内容指纹）
$manifestPath = Join-Path $Root 'update/versions.tsv'
$oldMap = @{}
if(Test-Path -LiteralPath $manifestPath){
    foreach($line in (Get-Content -LiteralPath $manifestPath)){
        if($line -match '^\s*$'){ continue }
        $cols = $line -split "`t"
        if($cols.Count -ge 3){ $oldMap[$cols[0]] = [pscustomobject]@{ Vc = [int]$cols[1]; Hash = $cols[2] } }
    }
}

# 重建 update 目录（全部确定性生成，未变化时 git 无 diff）
$updateDir = Join-Path $Root 'update'
if([IO.Directory]::Exists($updateDir)){ [IO.Directory]::Delete($updateDir, $true) }
[void][IO.Directory]::CreateDirectory($updateDir)
Write-Lf (Join-Path $updateDir 'README.md') @'
# update/

模块管理器更新信息（updateJson）目录，由 `tools/apply_update_metadata.ps1` 自动生成，请勿手改。

- `<模块id>.json`：Magisk / KernelSU / APatch 管理器的更新检查信息（version / versionCode / zipUrl）
- `versions.tsv`：全部模块的版本号与内容指纹
'@

$infra = @('.github','tools','_upstream','dist','update')
$brandDirs = @(Get-ChildItem -LiteralPath $Root -Directory | Where-Object { $_.Name -notin $infra -and -not $_.Name.StartsWith('.') })

$today = [int]([DateTime]::UtcNow.AddHours(8).ToString('yyyyMMdd'))
$dateBase = $today * 100

$rows = New-Object System.Collections.Generic.List[string]
$total = 0; $bumped = 0; $added = 0; $processed = 0

foreach($b in $brandDirs){
    $zips = @(Get-ChildItem -LiteralPath $b.FullName -Recurse -File -Filter *.zip | Sort-Object FullName)
    foreach($z in $zips){
        $total++
        $processed++
        $relZip = $z.FullName.Substring($Root.Length + 1).Replace([char]92,'/')

        # 读出 zip 全部条目到内存
        $entries = New-Object System.Collections.Generic.List[object]
        $zip = [IO.Compression.ZipFile]::OpenRead($z.FullName)
        try{
            foreach($e in $zip.Entries){
                $ms = New-Object IO.MemoryStream
                $s = $e.Open()
                try{ $s.CopyTo($ms) } finally { $s.Dispose() }
                $entries.Add([pscustomobject]@{ Name = $e.FullName; Bytes = $ms.ToArray() }) | Out-Null
                $ms.Dispose()
            }
        } finally { $zip.Dispose() }

        $propEntry = $entries | Where-Object { $_.Name -eq 'module.prop' } | Select-Object -First 1
        if(-not $propEntry){ Write-Warning ('无 module.prop: ' + $relZip); continue }
        $propText = [Text.Encoding]::UTF8.GetString($propEntry.Bytes)
        $id = ''
        if($propText -match '(?m)^id=(.+)$'){ $id = $Matches[1].Trim() }
        if(-not $id){ Write-Warning ('无 id: ' + $relZip); continue }

        # 内容指纹（忽略 module.prop 的 version/versionCode/updateJson 三行）
        $propNorm = (($propText -split "`n") | Where-Object { $_ -notmatch '^(version|versionCode|updateJson)=' }) -join "`n"
        $hashLines = New-Object System.Collections.Generic.List[string]
        foreach($e in $entries){
            $content = if($e.Name -eq 'module.prop'){ Get-TextBytes $propNorm } else { $e.Bytes }
            $hashLines.Add($e.Name + "`n" + (Get-HashHex $content))
        }
        $hashLines.Sort([StringComparer]::Ordinal)
        $payloadHash = Get-HashHex ([Text.Encoding]::UTF8.GetBytes(($hashLines -join "`n")))

        # 版本号：内容未变则沿用；变化/新增则递增（严格大于旧版本，保证管理器能识别更新）
        $old = $oldMap[$id]
        if($old -and $old.Hash -eq $payloadHash){
            $vc = $old.Vc
        } else {
            $baseVc = if($old){ $old.Vc } else { $LegacyVersionCode }
            $vc = [math]::Max($baseVc + 1, $dateBase + 1)
            if($old){ $bumped++ } else { $added++ }
        }
        $vcStr = $vc.ToString()
        $verStr = 'v' + $vcStr.Substring(0,4) + '.' + $vcStr.Substring(4,2) + '.' + $vcStr.Substring(6,2) + '.' + ($vc % 100)

        # 重写 module.prop（替换或追加 version / versionCode / updateJson）
        $updateUrl = $rawBase + 'update/' + $id + '.json'
        $rawLines = @($propText -split "`n")
        $trailing = $false
        if($rawLines.Count -gt 0 -and $rawLines[$rawLines.Count - 1] -eq ''){ $trailing = $true; $rawLines = @($rawLines[0..($rawLines.Count - 2)]) }
        $hadVersion = $false; $hadVc = $false; $hadUrl = $false
        $lines = New-Object System.Collections.Generic.List[string]
        foreach($ln in $rawLines){
            if($ln -match '^version='){ $lines.Add('version=' + $verStr); $hadVersion = $true }
            elseif($ln -match '^versionCode='){ $lines.Add('versionCode=' + $vc); $hadVc = $true }
            elseif($ln -match '^updateJson='){ $lines.Add('updateJson=' + $updateUrl); $hadUrl = $true }
            else { $lines.Add($ln) }
        }
        if(-not $hadVersion){ $lines.Add('version=' + $verStr) }
        if(-not $hadVc){ $lines.Add('versionCode=' + $vc) }
        if(-not $hadUrl){ $lines.Add('updateJson=' + $updateUrl) }
        $newProp = ($lines -join "`n")
        if($trailing){ $newProp += "`n" }
        $newPropBytes = Get-TextBytes $newProp

        $sameBytes = (Get-HashHex $propEntry.Bytes) -eq (Get-HashHex $newPropBytes)
        if(-not $sameBytes){
            foreach($e in $entries){ if($e.Name -eq 'module.prop'){ $e.Bytes = $newPropBytes } }
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('N') + '.zip')
            New-ZipFromEntryData $entries.ToArray() $tmp
            [IO.File]::Copy($tmp, $z.FullName, $true)
            [IO.File]::Delete($tmp)
        }

        # 写 update/<id>.json
        $zipUrl = $rawBase + ((($relZip -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/')
        $json = '{' + "`n" +
                '  "version": "' + $verStr + '",' + "`n" +
                '  "versionCode": ' + $vc + ',' + "`n" +
                '  "zipUrl": "' + $zipUrl + '"' + "`n" +
                '}' + "`n"
        Write-Lf (Join-Path $updateDir ($id + '.json')) $json

        $rows.Add($id + "`t" + $vc + "`t" + $payloadHash)

        if($processed % 500 -eq 0){ Write-Host ('已处理 ' + $processed + ' / ' + $total + ' ...') }
    }
}

$rows.Sort([StringComparer]::Ordinal)
Write-Lf $manifestPath (([string]::Join("`n", $rows)) + "`n")
Write-Host ('更新信息完成: 共 ' + $total + ' 个模块, 内容变化 ' + $bumped + ' 个, 新增 ' + $added + ' 个')
