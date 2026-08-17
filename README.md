# REDMI K90 (annibale) GKI + SukiSU

**完整复现说明（以这份为准）：[`BUILD-K90-GKI.md`](BUILD-K90-GKI.md)**

换新机器只带 seed：`SEED-FILES.txt` 里的文件，或 `bash scripts/pack-seed.sh` 打出来的 tar.gz。不要拷 `gki/` / `out/` / `third_party/`。

当前已验证可用的产物：

- 临时启动：`out/aosp-release/boot-lz4.img`
- AnyKernel3：`out/SukiSU-annibale-aosp-6.6.77-4k-SUSFS-REL-AnyKernel3.zip`

内核：`6.6.77-android15-8-4k`（AOSP r15 + 内置 SukiSU/KPM + SUSFS + RFKILL=y）。

不要用网上通用 GKI，会闪屏。不要用 `xiaomi/` OSS 当主构建。不要刷 16K。
