# 全品牌机型伪装 Magisk 模块批量生成器
# 数据源: https://github.com/KHwang9883/MobileModels (brands/*.md)
# 输出:   <OutRoot>/<品牌>/<机型 (代号)>/{模块源码 + 可刷 zip}
param(
    [string]$BrandsDir = "$PSScriptRoot/../_upstream/brands",
    [string]$OutRoot   = "$PSScriptRoot/..",
    [string]$Author    = "单走一个6",
    [switch]$NoZip,
    [switch]$ZipOnly,
    [switch]$Clean,     # 生成前清空本脚本管理的品牌目录（用于全量同步，确保上游已删除/改名的机型不残留）
    [switch]$NoMeta     # 不生成 机型索引.csv / README.txt
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
if(-not (Test-Path -LiteralPath $OutRoot)){ New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null }
$OutRoot = (Resolve-Path -LiteralPath $OutRoot).Path
if(Test-Path -LiteralPath $BrandsDir){ $BrandsDir = (Resolve-Path -LiteralPath $BrandsDir).Path }
if($NoZip -and $ZipOnly){ throw '$NoZip 与 $ZipOnly 不能同时使用' }
$partitions = @('system','system_ext','vendor','product','odm','bootimage','vendor_dlkm','odm_dlkm')

# ---------------- 品牌注册表 ----------------
$brands = @(
    [pscustomobject]@{ Folder='小米';                 Files=@('xiaomi.md');                                      Brand='';          Manu='';            XiaomiSpecial=$true  },
    [pscustomobject]@{ Folder='黑鲨';                 Files=@('blackshark_en.md','blackshark.md');               Brand='blackshark'; Manu='blackshark';  XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='OPPO';                 Files=@('oppo_cn.md','oppo_global_en.md');                 Brand='OPPO';       Manu='OPPO';        XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='vivo';                 Files=@('vivo_cn.md','vivo_global_en.md');                 Brand='vivo';       Manu='vivo';        XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='一加';                 Files=@('oneplus_en.md','oneplus.md');                     Brand='OnePlus';    Manu='OnePlus';     XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='realme';               Files=@('realme_cn.md','realme_global_en.md');             Brand='realme';     Manu='realme';      XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='三星';                 Files=@('samsung_cn.md','samsung_global_en.md');           Brand='samsung';    Manu='samsung';     XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='谷歌';                 Files=@('google.md');                                      Brand='google';     Manu='Google';      XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='华为';                 Files=@('huawei_cn.md','huawei_global_en.md');             Brand='HUAWEI';     Manu='HUAWEI';      XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='荣耀';                 Files=@('honor_cn.md','honor_global_en.md');               Brand='HONOR';      Manu='HONOR';       XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='索尼';                 Files=@('sony.md','sony_cn.md');                           Brand='Sony';       Manu='Sony';        XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='魅族';                 Files=@('meizu_en.md','meizu.md');                         Brand='meizu';      Manu='Meizu';       XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='摩托罗拉';             Files=@('motorola_cn.md');                                 Brand='motorola';   Manu='motorola';    XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='联想';                 Files=@('lenovo_cn.md');                                   Brand='Lenovo';     Manu='Lenovo';      XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='诺基亚';               Files=@('nokia_cn.md');                                    Brand='Nokia';      Manu='HMD Global';  XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='华硕';                 Files=@('asus_en.md','asus_cn.md');                        Brand='ASUS';       Manu='ASUSTeK';     XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='努比亚';               Files=@('nubia_cn.md','nubia_global_en.md');               Brand='nubia';      Manu='nubia';       XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='中兴';                 Files=@('zte_cn.md');                                      Brand='ZTE';        Manu='ZTE';         XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='酷派';                 Files=@('coolpad.md');                                     Brand='Coolpad';    Manu='Coolpad';     XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='乐视';                 Files=@('letv.md');                                        Brand='Letv';       Manu='Letv';        XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='锤子';                 Files=@('smartisan.md');                                   Brand='smartisan';  Manu='Smartisan';   XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='360';                  Files=@('360shouji.md');                                   Brand='360';        Manu='360';         XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='Nothing';              Files=@('nothing.md');                                     Brand='Nothing';    Manu='Nothing';     XiaomiSpecial=$false },
    [pscustomobject]@{ Folder='智选';                 Files=@('zhixuan.md');                                     Brand='智选';       Manu='智选';        XiaomiSpecial=$false }
)

# ---------------- 工具函数 ----------------
function Write-Lf([string]$Path,[string]$Text){
    $t = $Text -replace "`r`n","`n"
    $dir = Split-Path -Parent $Path
    if(-not (Test-Path -LiteralPath $dir)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($Path,$t,$utf8NoBom)
}

function Sanitize-Name([string]$s){
    if($null -eq $s){ return 'unknown' }
    $x = ($s -replace '[\\/:*?"<>|]','_').Trim().TrimEnd('.')
    if($x.Length -gt 110){ $x = $x.Substring(0,110).Trim() }
    if($x -eq ''){ $x = 'unknown' }
    return $x
}

function Sanitize-Id([string]$s){
    if($null -eq $s){ return 'unknown' }
    $x = $s.ToLowerInvariant() -replace '[^a-z0-9._-]','_'
    $x = $x.Trim('_')
    if($x -eq ''){ $x = 'unknown' }
    return $x
}

function Convert-XiaomiName([string]$n){
    $x = $n.Trim()
    if($x -match '^小米平板'){ $x = 'Xiaomi Pad' + $x.Substring(4) }
    elseif($x -match '^红米平板'){ $x = 'Redmi Pad' + $x.Substring(4) }
    elseif($x -match '^红米手机'){ $x = 'Redmi' }
    elseif($x -match '^小米'){ $x = 'Xiaomi' + $x.Substring(2) }
    elseif($x -match '^红米'){ $x = 'Redmi' + $x.Substring(2) }
    return $x.Trim()
}

function New-ZipFromDir([string]$SourceDir,[string]$ZipPath){
    $base = (Resolve-Path -LiteralPath $SourceDir).Path.TrimEnd([char]92,[char]47)
    # 按相对路径 ordinal 排序 + 固定时间戳：保证未变更的模块重复生成时字节完全一致
    $map = @{}
    foreach($f in (Get-ChildItem -LiteralPath $SourceDir -Recurse -File)){
        if($f.Extension -eq '.zip'){ continue }
        $rel = $f.FullName.Substring($base.Length + 1).Replace([char]92,'/')
        $map[$rel] = $f.FullName
    }
    $relList = New-Object 'System.Collections.Generic.List[string]'
    foreach($k in $map.Keys){ $relList.Add($k) }
    $relList.Sort([StringComparer]::Ordinal)
    $ts = [DateTimeOffset]::new(2020,1,1,0,0,0,[TimeSpan]::Zero)
    $fs = [IO.File]::Open($ZipPath,[IO.FileMode]::Create)
    try{
        $zip = New-Object System.IO.Compression.ZipArchive($fs,[IO.Compression.ZipArchiveMode]::Create)
        try{
            foreach($rel in $relList){
                $entry = $zip.CreateEntry($rel,[IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = $ts
                $es = $entry.Open()
                try{
                    $bytes = [IO.File]::ReadAllBytes($map[$rel])
                    $es.Write($bytes,0,$bytes.Length)
                } finally { $es.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $fs.Dispose() }
}

function Remove-ModuleSources([string]$Dir,[string]$KeepZip){
    Get-ChildItem -LiteralPath $Dir -Recurse -File -Force | Where-Object { $_.FullName -ne $KeepZip } | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force
    }
    Get-ChildItem -LiteralPath $Dir -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
        if((Get-ChildItem -LiteralPath $_.FullName -Force | Measure-Object).Count -eq 0){
            Remove-Item -LiteralPath $_.FullName -Force
        }
    }
}

function Get-DeviceRecords([string]$Path){
    $records = New-Object System.Collections.Generic.List[object]
    $cur = $null
    foreach($line in (Get-Content -LiteralPath $Path)){
        if($line -match '^\*\*(.+?):\*\*\s*$'){
            $name = $Matches[1].Trim()
            $name = $name -replace '^\[[^\]]*\]\s*',''
            $code = ''
            if($name -match '\s*\(`([^`]+)`\)\s*$'){
                $code = $Matches[1].Trim()
                $name = ($name -replace '\s*\(`[^`]+`\)\s*$','').Trim()
            }
            $name = ($name -split '\s*/\s*')[0].Trim()
            $cur = [pscustomobject]@{
                Name = $name
                Codename = $code
                Models = New-Object System.Collections.Generic.List[object]
            }
            $records.Add($cur) | Out-Null
            continue
        }
        if($cur -and $line -match '^`([^`]+)`:\s*(.+?)\s*$'){
            $cur.Models.Add([pscustomobject]@{ Model = $Matches[1].Trim(); Desc = $Matches[2].Trim() }) | Out-Null
        }
    }
    return $records
}

# ---------------- 模板 ----------------
$tplModuleProp = @'
id=@@ID@@
name=@@MARKET@@ 机型伪装 (Android 1-17)
version=v1.0-a1a17
versionCode=2026100402
author=@@AUTHOR@@
description=[Android 1-17适配] 将机型伪装为 @@MARKET@@ (@@MODEL@@)：管理器刷入走模块(6-17)，旧 recovery/手动脚本直改 build.prop(1-5)。
'@

$tplCustomize = @'
#!/system/bin/sh
# 新式模块安装回调：Magisk / KernelSU / APatch 通用

ui_print " -------------------------- "
ui_print "  @@MARKET@@ 机型伪装"
ui_print "  Android 1-17 适配版"
ui_print " -------------------------- "

for f in apply_props.sh post-fs-data.sh service.sh action.sh; do
	[ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0755
done
[ -f "$MODPATH/system.prop" ] && set_perm "$MODPATH/system.prop" 0 0 0644
[ -f "$MODPATH/module.prop" ] && set_perm "$MODPATH/module.prop" 0 0 0644

ui_print " - 安装完成，重启后生效"
ui_print " - 如已装旧版机型模块，请先卸载旧版"
ui_print " -------------------------- "
ui_print " -------------------------- "

if [ -x /system/bin/am ]; then
sleep 1
if /system/bin/pm list packages 2>/dev/null | grep -q '^package:com\.coolapk\.market$'; then
/system/bin/am start -d 'coolmarket://u/1429422' >/dev/null 2>&1 || \
/system/bin/am start -a android.intent.action.VIEW -d 'https://www.coolapk.com/u/1429422' >/dev/null 2>&1
else
/system/bin/am start -a android.intent.action.VIEW -d 'https://www.coolapk.com/u/1429422' >/dev/null 2>&1
fi
fi
'@

# KernelSU / APatch 模块「执行 / Action」按钮脚本
$tplAction = @'
#!/system/bin/sh

if /system/bin/pm list packages 2>/dev/null | grep -q '^package:com\.coolapk\.market$'; then
/system/bin/am start -d 'coolmarket://u/1429422' >/dev/null 2>&1
else
/system/bin/am start -a android.intent.action.VIEW -d 'https://www.coolapk.com/u/1429422' >/dev/null 2>&1
fi
'@

$tplApplyProps = @'
#!/system/bin/sh
# 机型属性应用脚本：由 post-fs-data.sh / service.sh 载入
# 覆盖 generic + system/system_ext/vendor/product/odm/bootimage/vendor_dlkm/odm_dlkm

RP=""
for c in resetprop /data/adb/magisk/resetprop /data/adb/ksu/bin/resetprop /data/adb/ap/bin/resetprop; do
	if [ -x "$c" ]; then RP="$c"; break; fi
	p="$(command -v "$c" 2>/dev/null)"
	if [ -n "$p" ] && [ -x "$p" ]; then RP="$p"; break; fi
done

get_prop() {
	if [ -n "$RP" ]; then
		"$RP" "$1" 2>/dev/null && return 0
	fi
	getprop "$1" 2>/dev/null
}

set_prop() {
	_n="$1"; _v="$2"
	[ "$(get_prop "$_n")" = "$_v" ] && return 0
	if [ -n "$RP" ]; then
		"$RP" -n "$_n" "$_v" 2>/dev/null && return 0
		_old="$(get_prop "$_n")"
		"$RP" --delete "$_n" 2>/dev/null || "$RP" -d "$_n" 2>/dev/null
		if "$RP" -n "$_n" "$_v" 2>/dev/null || "$RP" "$_n" "$_v" 2>/dev/null; then
			return 0
		fi
		[ -n "$_old" ] && "$RP" "$_n" "$_old" 2>/dev/null
	fi
	if command -v magisk >/dev/null 2>&1 && magisk resetprop -n "$_n" "$_v" 2>/dev/null; then
		return 0
	fi
	if command -v ksud >/dev/null 2>&1 && ksud resetprop -n "$_n" "$_v" 2>/dev/null; then
		return 0
	fi
	setprop "$_n" "$_v" 2>/dev/null
}

@@ASSIGN@@
'@

$tplPostFs = @'
#!/system/bin/sh
# post-fs-data：Zygote 启动前应用，确保 Build.* 与系统服务读取到新值
MODDIR=${0%/*}
[ -f "$MODDIR/apply_props.sh" ] && . "$MODDIR/apply_props.sh"
'@

$tplService = @'
#!/system/bin/sh
# service：开机后再校验一次，防止系统组件或 OEM 服务回写属性
MODDIR=${0%/*}
[ -f "$MODDIR/apply_props.sh" ] && . "$MODDIR/apply_props.sh"
'@

$tplUpdateBinary = @'
#!/sbin/sh
# 三合一安装入口（@@MARKET@@ 机型伪装，Android 1-17）
# 1) Magisk/KernelSU/APatch 管理器刷入：执行 customize.sh（模块模式，Android 5-17）
# 2) 管理器/恢复环境把本文件当 legacy 安装器执行：直接把模块文件落到 /data/adb/modules(_update)
# 3) 旧 recovery 且设备没有 root 方案：直接修改 /system/build.prop（Android 1.x-5.x）

OUTFD=$2
ZIPFILE=$3
ui_print() { printf 'ui_print %s\nui_print\n' "$1" > /proc/self/fd/$OUTFD 2>/dev/null; }

ui_print "*******************************"
ui_print " @@MARKET@@ 机型伪装 (Android 1-17)"
ui_print "*******************************"

mount /data >/dev/null 2>&1

# ---------- root 方案环境：直接落地模块文件 ----------
if [ -f /data/adb/magisk/util_functions.sh ] || [ -d /sbin/.magisk ] || [ -d /data/adb/ksu ] || [ -d /data/adb/ap ]; then
	MODROOT=/data/adb/modules
	[ "$BOOTMODE" = "true" ] && MODROOT=/data/adb/modules_update
	MODPATH=$MODROOT/@@ID@@
	if [ -n "$ZIPFILE" ] && [ -f "$ZIPFILE" ]; then
		UNZIP=""
		if command -v unzip >/dev/null 2>&1; then UNZIP=unzip
		elif [ -x /sbin/busybox ]; then UNZIP="/sbin/busybox unzip"
		elif [ -x /system/bin/toybox ]; then UNZIP="/system/bin/toybox unzip"
		fi
		if [ -n "$UNZIP" ]; then
			rm -rf "$MODPATH" 2>/dev/null
			mkdir -p "$MODPATH" 2>/dev/null
			$UNZIP -o "$ZIPFILE" -x 'META-INF/*' -d "$MODPATH" >/dev/null 2>&1
			if [ -f "$MODPATH/module.prop" ]; then
				for f in apply_props.sh post-fs-data.sh service.sh action.sh; do
					chmod 0755 "$MODPATH/$f" 2>/dev/null
				done
				chmod 0644 "$MODPATH/module.prop" "$MODPATH/system.prop" 2>/dev/null
				ui_print "- 模块已释放到 $MODPATH"
				ui_print "- 重启后机型生效"
				if [ -x /system/bin/am ]; then
					/system/bin/am start -d 'coolmarket://u/1429422' >/dev/null 2>&1 || \
					/system/bin/am start -a android.intent.action.VIEW -d 'https://www.coolapk.com/u/1429422' >/dev/null 2>&1
				fi
				exit 0
			fi
		fi
	fi
	ui_print "! 自动安装失败，请在 Magisk/KernelSU/APatch 管理器中刷入"
	exit 1
fi

# ---------- 旧系统 recovery：直接改 build.prop ----------
ui_print "- 未检测到 root 方案，尝试 build.prop 直改模式"
mount -o rw,remount /system >/dev/null 2>&1
[ -f /system/build.prop ] || mount /system >/dev/null 2>&1
[ -f /system/build.prop ] || /sbin/busybox mount /system >/dev/null 2>&1
if [ ! -f /system/build.prop ]; then
	ui_print "! 无法挂载 /system，未做任何修改"
	exit 1
fi

BP=/system/build.prop
SDK=$(sed -n 's/^ro\.build\.version\.sdk=//p' "$BP" 2>/dev/null | head -n 1)
case "$SDK" in ''|*[!0-9]*) SDK=0 ;; esac
if [ "$SDK" -ge 23 ]; then
	ui_print "- 检测到 Android 6.0+ (SDK $SDK)，不建议直改 build.prop"
	ui_print "- 请在 Magisk/KernelSU/APatch 管理器中刷入本 zip"
	exit 0
fi

[ -f "$BP.xj_bak" ] || cp -f "$BP" "$BP.xj_bak" 2>/dev/null
while IFS= read -r line; do
	case "$line" in
		ro.product.brand=*|ro.product.manufacturer=*|ro.product.model=*|ro.product.name=*|ro.product.marketname=*) ;;
		*) echo "$line" ;;
	esac
done < "$BP" > "$BP.xj_tmp"
if [ ! -s "$BP.xj_tmp" ]; then
	rm -f "$BP.xj_tmp"
	ui_print "! 处理失败，未做任何修改"
	exit 1
fi
{
	cat "$BP.xj_tmp"
	echo "ro.product.brand=@@BRAND@@"
	echo "ro.product.manufacturer=@@MANU@@"
	echo "ro.product.model=@@MODEL@@"
	echo "ro.product.name=@@CODENAME@@"
	echo "ro.product.marketname=@@MARKET@@"
} > "$BP.xj_new"
cat "$BP.xj_new" > "$BP"
rm -f "$BP.xj_tmp" "$BP.xj_new"
sync 2>/dev/null
ui_print "- 已写入 build.prop（备份：/system/build.prop.xj_bak）"
ui_print "- 重启后机型生效"
exit 0
'@

$tplUpdaterScript = @'
#XJ-LEGACY
# 安装入口：META-INF/com/google/android/update-binary（shell）
'@

$tplLegacyApply = @'
#!/system/bin/sh
# @@MARKET@@ 机型伪装（Android 1.x-5.x 手动模式）
# 用法（需要 root）：su -c 'sh /sdcard/xj_apply.sh'
# 自动备份为 /system/build.prop.xj_bak，重复执行安全

BP=/system/build.prop
echo "[*] 机型伪装 -> @@MARKET@@ (@@MODEL@@)"

mount -o rw,remount /system 2>/dev/null
[ -f "$BP" ] || mount /system 2>/dev/null
if [ ! -f "$BP" ]; then
	echo "[!] 找不到 $BP（无法挂载 /system）"
	exit 1
fi
touch /system/.xj_write_test 2>/dev/null
if [ ! -f /system/.xj_write_test ]; then
	echo "[!] /system 只读，无法修改"
	exit 1
fi
rm -f /system/.xj_write_test

[ -f "$BP.xj_bak" ] || cp -f "$BP" "$BP.xj_bak"

while IFS= read -r line; do
	case "$line" in
		ro.product.brand=*|ro.product.manufacturer=*|ro.product.model=*|ro.product.name=*|ro.product.marketname=*) ;;
		*) echo "$line" ;;
	esac
done < "$BP" > "$BP.xj_tmp"
if [ ! -s "$BP.xj_tmp" ]; then
	rm -f "$BP.xj_tmp"
	echo "[!] 处理失败，未做修改"
	exit 1
fi
{
	cat "$BP.xj_tmp"
	echo "ro.product.brand=@@BRAND@@"
	echo "ro.product.manufacturer=@@MANU@@"
	echo "ro.product.model=@@MODEL@@"
	echo "ro.product.name=@@CODENAME@@"
	echo "ro.product.marketname=@@MARKET@@"
} > "$BP.xj_new"
cat "$BP.xj_new" > "$BP"
rm -f "$BP.xj_tmp" "$BP.xj_new"
sync 2>/dev/null
echo "[+] 完成，重启后生效；备份：$BP.xj_bak"
'@

$tplLegacyRestore = @'
#!/system/bin/sh
# 还原 @@MARKET@@ 机型伪装（Android 1.x-5.x 手动模式）
# 用法（需要 root）：su -c 'sh /sdcard/xj_restore.sh'

BP=/system/build.prop
mount -o rw,remount /system 2>/dev/null
if [ ! -f "$BP.xj_bak" ]; then
	echo "[!] 未找到备份 $BP.xj_bak"
	exit 1
fi
cat "$BP.xj_bak" > "$BP"
rm -f "$BP.xj_bak"
sync 2>/dev/null
echo "[+] 已还原，重启后生效"
'@

$tplLegacyReadme = @'
@@MARKET@@ 机型伪装 - 老系统（Android 1.x-5.x）说明
================================================

1. Android 6-17：Magisk / KernelSU / APatch 管理器刷入同目录 zip，重启生效。
2. Android 2.2-5.x：CWM / TWRP 直接刷 zip（自动改 /system/build.prop，备份 .xj_bak）。
3. Android 1.x-5.x 手动：root 终端执行
       su -c 'sh /sdcard/xj_apply.sh'     # 应用
       su -c 'sh /sdcard/xj_restore.sh'   # 还原
'@

$tplReadme = @'
# @@MARKET@@ 机型伪装（Android 1-17 适配版）

- 目标机型: @@MARKET@@
- 型号号: @@MODEL@@
- 代号: @@CODENAME@@
- 品牌: @@BRAND@@ (manufacturer=@@MANU@@)
- 模块 id: @@ID@@

## 安装

1. Android 6-17：Magisk / KernelSU / APatch 管理器刷入本文件夹内的 zip，重启。
2. Android 2.2-5.x：CWM / TWRP 直接刷同一个 zip（自动改写 build.prop，先备份 .xj_bak）。
3. Android 1.x-5.x 手动：见 legacy/ 目录（xj_apply.sh / xj_restore.sh）。

## 校验

getprop ro.product.model 应为 @@MODEL@@，getprop ro.product.marketname 应为 @@MARKET@@。

## 更新

模块内置更新信息：刷入后可在 Magisk / KernelSU / APatch 管理器里直接检查并安装新版本。

## 同机型其它可用型号号（改 system.prop / apply_props.sh 即可替换）

@@VARIANTS@@
'@

# ---------------- 生成 ----------------
$exclude = '手表|手环|Watch|Buds|FreeBuds|耳机|眼镜|Glass|智慧屏|电视|TV|音箱|音响|路由|体脂|门锁|学习机|笔记本|Book|(?<!平板)电脑|VR|汽车'
$usedIds = @{}
$usedFolders = @{}
$seen = @{}
$index = New-Object System.Collections.Generic.List[object]
$dev = 0
$zipN = 0
$skipped = 0

$managedFolders = @($brands | ForEach-Object { $_.Folder }) + @('POCO','红米') | Select-Object -Unique

# 全量同步模式：先清空管理的品牌目录，确保上游已删除/改名的机型不会残留
if($Clean){
    foreach($folder in $managedFolders){
        $p = Join-Path $OutRoot $folder
        if(Test-Path -LiteralPath $p){ Remove-Item -LiteralPath $p -Recurse -Force }
    }
}

# 先建品牌根目录
foreach($b in $brands){ New-Item -ItemType Directory -Force -Path (Join-Path $OutRoot $b.Folder) | Out-Null }

foreach($brand in $brands){
    foreach($file in $brand.Files){
        $path = Join-Path $BrandsDir $file
        if(-not (Test-Path -LiteralPath $path)){ Write-Host ("missing file: " + $file); continue }
        $records = Get-DeviceRecords $path
        foreach($rec in $records){
            if($rec.Models.Count -eq 0){ $skipped++; continue }
            if($rec.Name -match $exclude){ $skipped++; continue }

            # 品牌 / 目录 / 显示名
            if($brand.XiaomiSpecial){
                $market = Convert-XiaomiName $rec.Name
                if($rec.Name -match '^POCO'){
                    $folder = 'POCO'; $bBrand = 'POCO'; $bManu = 'Xiaomi'
                } elseif($rec.Name -match '^(红米|Redmi|REDMI)'){
                    $folder = '红米'; $bBrand = 'Redmi'; $bManu = 'Xiaomi'
                } else {
                    $folder = '小米'; $bBrand = 'Xiaomi'; $bManu = 'Xiaomi'
                }
            } else {
                $market = $rec.Name
                $folder = $brand.Folder; $bBrand = $brand.Brand; $bManu = $brand.Manu
            }
            if($market -eq ''){ $skipped++; continue }

            $model = $rec.Models[0].Model
            $code = $rec.Codename
            if($code -eq ''){ $code = Sanitize-Id $model }

            # 跨文件去重（同一品牌 CN/EN 文件中的同一设备）
            $key = $folder.ToLowerInvariant() + '|' + $code.ToLowerInvariant()
            if($seen.ContainsKey($key) -and $seen[$key] -ne $file){ $skipped++; continue }
            $seen[$key] = $file

            $idBase = 'xj_' + (Sanitize-Id $code)
            $id = $idBase
            $n = 2
            while($usedIds.ContainsKey($id)){ $id = $idBase + '_' + $n; $n++ }
            $usedIds[$id] = $true

            $brandDir = Join-Path $OutRoot $folder
            New-Item -ItemType Directory -Force -Path $brandDir | Out-Null
            $folderBase = Sanitize-Name ($market + ' (' + $code + ')')
            $folderName = $folderBase
            $n = 2
            while($usedFolders.ContainsKey(($folder + '|' + $folderName))){
                $folderName = $folderBase + ' #' + $n
                $n++
            }
            $usedFolders[($folder + '|' + $folderName)] = $true
            $dir = Join-Path $brandDir $folderName
            New-Item -ItemType Directory -Force -Path $dir | Out-Null

            $vt = New-Object System.Collections.Generic.List[string]
            $vt.Add('| 型号 | 说明 |')
            $vt.Add('|---|---|')
            foreach($m in $rec.Models){ $vt.Add('| ' + $m.Model + ' | ' + $m.Desc + ' |') }
            $variants = [string]::Join("`n", $vt)

            $sp = New-Object System.Collections.Generic.List[string]
            $sp.Add('# ' + $market + ' 机型伪装')
            $sp.Add('# Android 13+ / 15 / 16 / 17：generic 与各分区属性同时覆盖')
            $sp.Add('ro.product.manufacturer=' + $bManu)
            $sp.Add('ro.product.brand=' + $bBrand)
            $sp.Add('ro.product.marketname=' + $market)
            $sp.Add('ro.product.model=' + $model)
            $sp.Add('ro.product.name=' + $code)
            $sp.Add('# 保持原系统 device 代号不变')
            foreach($p in $partitions){
                $sp.Add('')
                $sp.Add('ro.product.' + $p + '.manufacturer=' + $bManu)
                $sp.Add('ro.product.' + $p + '.brand=' + $bBrand)
                $sp.Add('ro.product.' + $p + '.marketname=' + $market)
                $sp.Add('ro.product.' + $p + '.model=' + $model)
                $sp.Add('ro.product.' + $p + '.name=' + $code)
            }
            $systemProp = [string]::Join("`n", $sp)

            $as = New-Object System.Collections.Generic.List[string]
            foreach($p in $partitions){
                $as.Add('	set_prop "ro.product.' + $p + '.manufacturer" "' + $bManu + '"')
                $as.Add('	set_prop "ro.product.' + $p + '.brand" "' + $bBrand + '"')
                $as.Add('	set_prop "ro.product.' + $p + '.marketname" "' + $market + '"')
                $as.Add('	set_prop "ro.product.' + $p + '.model" "' + $model + '"')
                $as.Add('	set_prop "ro.product.' + $p + '.name" "' + $code + '"')
            }
            $as.Add('set_prop ro.product.manufacturer ' + $bManu)
            $as.Add('set_prop ro.product.brand ' + $bBrand)
            $as.Add('set_prop ro.product.marketname "' + $market + '"')
            $as.Add('set_prop ro.product.model ' + $model)
            $as.Add('set_prop ro.product.name ' + $code)
            $assign = [string]::Join("`n", $as)

            $modulePropText = $tplModuleProp.Replace('@@ID@@',$id).Replace('@@MARKET@@',$market).Replace('@@MODEL@@',$model).Replace('@@AUTHOR@@',$Author)
            $customizeText  = $tplCustomize.Replace('@@MARKET@@',$market)
            $applyText      = $tplApplyProps.Replace('@@ASSIGN@@',$assign)
            $updateBinText  = $tplUpdateBinary.Replace('@@MARKET@@',$market).Replace('@@ID@@',$id).Replace('@@BRAND@@',$bBrand).Replace('@@MANU@@',$bManu).Replace('@@MODEL@@',$model).Replace('@@CODENAME@@',$code)
            $legacyApplyText= $tplLegacyApply.Replace('@@MARKET@@',$market).Replace('@@BRAND@@',$bBrand).Replace('@@MANU@@',$bManu).Replace('@@MODEL@@',$model).Replace('@@CODENAME@@',$code)
            $legacyRestoreText = $tplLegacyRestore.Replace('@@MARKET@@',$market)
            $legacyReadmeText  = $tplLegacyReadme.Replace('@@MARKET@@',$market)
            $readmeText = $tplReadme.Replace('@@MARKET@@',$market).Replace('@@MODEL@@',$model).Replace('@@CODENAME@@',$code).Replace('@@BRAND@@',$bBrand).Replace('@@MANU@@',$bManu).Replace('@@ID@@',$id).Replace('@@VARIANTS@@',$variants)

            Write-Lf (Join-Path $dir 'module.prop') $modulePropText
            Write-Lf (Join-Path $dir 'customize.sh') $customizeText
            Write-Lf (Join-Path $dir 'system.prop') $systemProp
            Write-Lf (Join-Path $dir 'apply_props.sh') $applyText
            Write-Lf (Join-Path $dir 'post-fs-data.sh') $tplPostFs
            Write-Lf (Join-Path $dir 'service.sh') $tplService
            Write-Lf (Join-Path $dir 'action.sh') $tplAction
            Write-Lf (Join-Path $dir 'README.md') $readmeText
            Write-Lf (Join-Path $dir 'META-INF/com/google/android/update-binary') $updateBinText
            Write-Lf (Join-Path $dir 'META-INF/com/google/android/updater-script') $tplUpdaterScript
            Write-Lf (Join-Path $dir 'legacy/xj_apply.sh') $legacyApplyText
            Write-Lf (Join-Path $dir 'legacy/xj_restore.sh') $legacyRestoreText
            Write-Lf (Join-Path $dir 'legacy/README.txt') $legacyReadmeText

            $zipName = (Sanitize-Name ($market + ' (' + $model + ')')) + '.zip'
            if(-not $NoZip){
                $tmpZip = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('N') + '.zip')
                New-ZipFromDir $dir $tmpZip
                Move-Item -LiteralPath $tmpZip -Destination (Join-Path $dir $zipName) -Force
                $zipN++
                if($ZipOnly){ Remove-ModuleSources $dir (Join-Path $dir $zipName) }
            }

            $index.Add([pscustomobject]@{
                '品牌目录' = $folder
                '品牌'     = $bBrand
                '厂商'     = $bManu
                '机型'     = $market
                '型号'     = $model
                '代号'     = $code
                '文件夹'   = $dir
                'zip'      = $zipName
                '数据文件' = $file
            }) | Out-Null

            $dev++
            if($dev % 100 -eq 0){ Write-Host ("已生成 " + $dev + " ... 当前: " + $folder + " / " + $market) }
        }
    }
}

if(-not $NoMeta){
    $index | Export-Csv -LiteralPath (Join-Path $OutRoot '机型索引.csv') -Encoding UTF8 -NoTypeInformation

    $readmeRoot = New-Object System.Collections.Generic.List[string]
    $readmeRoot.Add('全品牌机型伪装 Magisk 模块合集')
    $readmeRoot.Add('========================================')
    $readmeRoot.Add('')
    $readmeRoot.Add('结构: <品牌>\<机型 (代号)>\')
    $readmeRoot.Add('每个文件夹 = 一个独立 Magisk 模块（源码 + 同目录可直接刷入的 zip）')
    $readmeRoot.Add('模块作者: ' + $Author)
    $readmeRoot.Add('系统支持: Android 1-17（6-17 管理器模块；1-5 build.prop 直改）')
    $readmeRoot.Add('索引文件: 机型索引.csv')
    $readmeRoot.Add('数据来源: https://github.com/KHwang9883/MobileModels (brands/*.md)')
    $readmeRoot.Add('')
    $readmeRoot.Add('生成数量: ' + $dev + ' 个机型; 跳过(非手机/重复/无型号): ' + $skipped + ' 个')
    Write-Lf (Join-Path $OutRoot 'README.txt') ([string]::Join("`n", $readmeRoot))
}

Write-Host ("完成: 生成 " + $dev + " 个机型模块, 打包 " + $zipN + " 个 zip, 跳过 " + $skipped)
Write-Host ("输出目录: " + (Resolve-Path -LiteralPath $OutRoot).Path)
if(-not (Test-Path -LiteralPath $OutRoot)){ New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null }
$OutRoot = (Resolve-Path -LiteralPath $OutRoot).Path
