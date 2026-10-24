# K90 BakaSU GKI 构建手册

本分支（`bakasu-gki-fresh`）是**全新流水线**，不继承 main 的任何历史：BakaSU（ReSukiSU，官方 KernelSU v3.x 架构 + 原生 SUSFS 菜单）+ SUSFS + Droidspaces 容器配置。

已验证事实（2026-10-24 预检 + dry-run）：

- `susfs@bd7d199a` 的 50_ 打 r15 树需 --fuzz=3（base.c hunk）。BakaSU 基座在官方 preinit API 合入前，现行 susfs HEAD 的 50_ 引用 `ksu_preinit_*` 会链接失败——这就是 pin 的原因。BakaSU **main 分支 10-10 起封禁 susfs 构建**（susfs_compat.mk 无条件 error，作者挂起等 simonpunk 同步）；默认用 **sync-susfs 分支**（解封现场，Kbuild 无 error）。
- BakaSU **原生自带 KSU_SUSFS Kconfig 菜单**（10 项）→ 不需要 susfs 的 10_ 驱动补丁。
- Droidspaces kABI 补丁上下文 = AOSP r15 原味 sched.h（1075/1508 行）。
- CFS_BANDWIDTH / CGROUP_PIDS 无 padding 可救（约 4k 符号 CRC），**永久禁用**——`--cpus`/`--pids-limit` 放弃。

## 构建

```bash
cd "$ROOT"
sudo bash scripts/00-install-deps.sh   # 含 apt-get update（修镜像索引 404）
bash scripts/01-sync-aosp-gki.sh        # repo init common-android15-6.6 → pin r15
bash scripts/02-apply-bakasu.sh         # BakaSU + susfs(50_) + kABI + fragment + SUSFS 菜单
bash scripts/03-apply-gki-tuning.sh     # RFKILL=y、TTL/HL、去 dirty、protected_exports
AOSP_DIST="$ROOT/out/aosp-release" BUILD_JOBS=3 LTO=thin \
  bash scripts/04-build-gki.sh
bash scripts/05-pack-anykernel.sh
```

CI：Actions "Build K90 GKI (BakaSU)"，输入 `ksu_tag`（空 = **sync-susfs 分支**）/ `susfs_commit`（空 = 配套 pin `bd7d199a`）/ `lto` / `jobs` / `create_release`。

## 验收

```
fastboot boot out/aosp-release/boot.img
```

- `uname -r` = `6.6.77-android15-8-g4a507830d890-4k`
- 管理器：**ReSukiSU / BakaSU APK**（不是官方 KernelSU 也不是 SukiSU）
- Droidspaces 检查单：除 `--cpus`/`--pids-limit` 两项外应全绿
- 容器玩法前在管理器里关掉 SUSFS 的 "hide sus mounts for all processes"

## 升级注意

- **BakaSU sync-upstream 带入官方 preinit API 后**：susfs 可解除 `bd7d199a` pin 跟随 HEAD（届时现行 50_ 的 preinit 引用能链接上）。判断方法：BakaSU 仓库出现 `kernel/preinit/` 目录且含 `ksu_preinit_handle_post_execveat`。
- 升级 susfs commit 前先本地 dry-run 50_：`patch -p1 --dry-run < 50_add_susfs_in_gki-android15-6.6.patch` 对 BakaSU 树跑一遍，0 失败再上 CI。
