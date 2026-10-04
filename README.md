<div align="center">

# 📱 全机型机型伪装 · Magisk 模块合集

**全品牌机型伪装模块 · Android 1 ~ 17 全兼容 · 纯本地脚本 · 无联网 · 每日自动同步上游机型数据**

一键把手机伪装成任意目标机型 —— `manufacturer / brand / model / name / marketname` 全分区覆盖

<img src="https://img.shields.io/badge/Android-1%20~%2017-3DDC84?style=for-the-badge&logo=android&logoColor=white" />
<img src="https://img.shields.io/badge/Magisk%20%7C%20KernelSU%20%7C%20APatch-Supported-00AF9A?style=for-the-badge" />
<img src="https://img.shields.io/badge/Sync-Auto%20Daily-FFC75F?style=for-the-badge&logo=githubactions&logoColor=white" />
<img src="https://img.shields.io/badge/Network-None-2088FF?style=for-the-badge" />
<img src="https://img.shields.io/badge/License-MIT-F472B6?style=for-the-badge" />

</div>

---

## ✨ 这是什么

- **主流品牌全收录**：vivo、三星、OPPO、华为、小米、红米、荣耀、一加…… 每个机型一个独立、可直接刷入的 Magisk 模块 zip；
- 刷入后把 `ro.product.*` 系列属性伪装为目标机型，覆盖 **generic + system / system_ext / vendor / product / odm / bootimage / vendor_dlkm / odm_dlkm** 各分区属性；
- `post-fs-data`（Zygote 启动前）+ `service`（开机后）双阶段写入，防止系统组件把属性回写；
- **Android 1 ~ 17 全兼容**：Android 6-17 走管理器模块；Android 2.2-5.x 走 recovery 直改 `build.prop`；Android 1.x-5.x 可手动执行 `legacy/` 脚本；
- 纯 shell 脚本，**无联网、无遥测、不上传任何数据**；
- 每个 zip 内自带完整源码（`apply_props.sh` / `system.prop` / `module.prop` 等），同机型可自行改型号替换。

> 🎯 一句话：**找到你的目标机型文件夹 → 刷入里面的 zip → 重启 → 机型变了。**

---

## 📦 仓库结构

```
Magisk-DeviceSpoofer/
├── 小米/
│   └── Xiaomi 14 (houji)/
│       └── Xiaomi 14 (23127PN0CC).zip   ← 独立 Magisk 模块（源码 + 安装脚本全在 zip 内）
├── 红米/
├── 三星/
├── vivo/
└── ...（共 26 个品牌目录）
```

- 目录名 = `品牌 / 机型 (代号)`；
- zip 名 = `机型 (型号)`，**每个 zip 都是完整模块**，管理器直接刷入即可；
- 想伪装成某个型号？在仓库里搜索型号（如 `23127PN0CC`）或代号（如 `houji`）即可定位；
- 部分机型 zip 内的 `README.md` 列有该机型其它可用型号号（改两个文件即可替换）。

### 品牌与机型数量

<!-- BRAND_STATS:BEGIN -->

| 品牌 | 数量 | 品牌 | 数量 |
| :--- | ---: | :--- | ---: |
| vivo | 548 | 华硕 | 72 |
| 三星 | 468 | 中兴 | 71 |
| OPPO | 330 | 摩托罗拉 | 59 |
| 华为 | 307 | 索尼 | 51 |
| 荣耀 | 279 | 酷派 | 46 |
| 红米 | 277 | 智选 | 42 |
| realme | 229 | 谷歌 | 40 |
| 小米 | 158 | 360 | 26 |
| 努比亚 | 106 | 诺基亚 | 17 |
| 联想 | 101 | 锤子 | 14 |
| 一加 | 95 | 黑鲨 | 14 |
| POCO | 87 | Nothing | 13 |
| 魅族 | 86 | 乐视 | 12 |

**合计：3548 个机型 / 26 个品牌**

<!-- BRAND_STATS:END -->

---

## 🚀 安装

### ⬇️ 下载

- **[Releases（推荐）](https://github.com/L0NE-6/Magisk-DeviceSpoofer/releases/latest)**：按品牌整包 / 全量合集 / 机型索引 CSV / SHA256 校验文件，全部由 Actions 自动构建；
- 或直接在仓库目录树点开 `品牌/机型 (代号)/` 下载单个机型 zip。

### Android 6 ~ 17（推荐）

1. 下载目标机型的 zip（管理器内直接下载，或 `git clone` 后从本地导入）；
2. Magisk / KernelSU / APatch 管理器 → 模块 → 从本地安装；
3. 重启，机型生效。

> 如已装其它机型伪装模块，**先卸载旧的再刷新的**：同类模块只保留一个。

### Android 2.2 ~ 5.x

- CWM / TWRP 直接刷同一个 zip：检测不到现代 root 方案时，安装器会自动直改 `/system/build.prop`（先备份为 `build.prop.xj_bak`）。

### Android 1.x ~ 5.x（手动）

- 解压 zip，见 `legacy/` 目录：
  - `xj_apply.sh`：应用伪装（自动备份 `build.prop.xj_bak`，重复执行安全）；
  - `xj_restore.sh`：还原。

### 校验

```sh
getprop ro.product.model       # 应输出目标型号，如 23127PN0CC
getprop ro.product.marketname  # 应输出目标机型名，如 Xiaomi 14
```

### 还原

- 模块版：管理器里停用 / 卸载模块 → 重启；
- 老系统：`su -c 'sh /sdcard/xj_restore.sh'` → 重启（自动还原 `build.prop.xj_bak`）。

---

## ⚙️ 工作原理

- 模块通过 `resetprop`（自动探测 Magisk / KernelSU / APatch 路径）写入属性，各分区属性同时覆盖；
- `post-fs-data.sh` 在 Zygote 启动前应用，保证 `Build.*` 与系统服务读到新值；
- `service.sh` 开机后再校验一次，防止 OEM 服务回写；
- 老系统安装器检测 SDK ≤ 22 时自动走 `build.prop` 直改分支（自动备份，可还原）。

---

## ⚠️ 注意事项

- 需要 root（Magisk / KernelSU / APatch 任一）；
- **一次只保留一个机型伪装模块**，多个同装会互相覆盖，结果不可预期；
- 伪装机型属于系统级属性修改，**部分应用（推送、商店、支付、游戏等）可能受机型影响**，出现异常先卸载模块并重启还原；
- 不同设备对 `ro.product.*` 属性的回写行为不同，极少数机型可能需要在其它阶段补写入；
- 刷机有风险，操作前请备份重要数据，后果自行承担。

---

## 🙏 数据来源

- 机型数据来自 **[KHwang9883/MobileModels](https://github.com/KHwang9883/MobileModels)**（CC BY-NC-SA 4.0）：手机品牌 / 机型 / 型号 / 代号汇总；
- 本仓库将上述数据批量化生成为独立 Magisk 模块，**免费分享、无任何商业用途**；
- 代码与脚本部分：MIT；机型数据部分遵循原数据 CC BY-NC-SA 4.0 许可。

---

## 🤖 自动同步

- GitHub Actions 每日 **02:30（北京时间）** 拉取 [MobileModels](https://github.com/KHwang9883/MobileModels) 最新 `brands/*.md`，自动重建全部模块并提交，未变化的机型不会产生任何改动；
- 同步产生变更时会自动发布一个**新版本 Release**（`v1`、`v2`、`v3`… 依次递增，每次更新独立成版、不覆盖不合并；全量合集 + 按品牌整包 + 机型索引 CSV + SHA256 校验文件）；
- 相关文件：生成脚本 [`tools/generate_all_brand_modules.ps1`](tools/generate_all_brand_modules.ps1) · 同步脚本 [`tools/sync_from_upstream.ps1`](tools/sync_from_upstream.ps1) · 工作流 [`.github/workflows/sync-modules.yml`](.github/workflows/sync-modules.yml)；
- 手动触发：**Actions → Sync modules from MobileModels → Run workflow**（`force` 强制重建，`dry_run` 只生成不提交）。

---

## 💬 反馈与贡献

- [提交 Issue](https://github.com/L0NE-6/Magisk-DeviceSpoofer/issues/new) —— 报 bug、求机型、提需求；
- [发起 Pull Request](https://github.com/L0NE-6/Magisk-DeviceSpoofer/pulls) —— 改动越具体越好。

---

## 📄 License

代码部分 [MIT](LICENSE) © 2026 L0NE-6；机型数据部分 © [MobileModels](https://github.com/KHwang9883/MobileModels)（CC BY-NC-SA 4.0）。
