# REDMI K90 (annibale) GKI + SukiSU

**完整复现说明（以这份为准）：[`BUILD-K90-GKI.md`](BUILD-K90-GKI.md)**

构建走 GitHub Actions。不要把 `gki/` / `out/` / `third_party/` 提交进仓库。

当前已验证可用的产物：

- 临时启动：`out/aosp-release/boot.img`（未压缩 Image；`boot-lz4.img` 在这台机上不能 `fastboot boot`）
- 临时启动（已打 KPM）：`out/aosp-release/boot-kpm.img`
- AnyKernel3：`out/SukiSU-annibale-aosp-6.6.77-4k-SUSFS-REL-AnyKernel3.zip`
- AnyKernel3（已打 KPM）：`out/SukiSU-annibale-aosp-6.6.77-4k-SUSFS-REL-KPM-AnyKernel3.zip`

内核：`6.6.77-android15-8-4k`（AOSP r15 + 内置 SukiSU/KPM + SUSFS + RFKILL=y）。

不要用网上通用 GKI，会闪屏。不要用小米 OSS 当主构建。不要刷 16K。
