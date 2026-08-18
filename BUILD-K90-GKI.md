# REDMI K90 (annibale) 可用 GKI 编译手册

下次编译先读这份。按第 3 节命令顺序做，可以编出已在真机验证过的包。不要按旧 `README.md` 的「只加 SukiSU、不加 SUSFS」流程。

已验证产物：`out/aosp-release/boot.img`（未压缩 Image）  
已验证启动：`fastboot boot boot.img`（`boot-lz4.img` / `boot-kpm-lz4.img` 在 annibale 上不能引导）  
已验证 `uname -r`：`6.6.77-android15-8-4k`  
真机日志（当时在编译机上）：`/home/admin/log3/`

构建以 GitHub 仓库 + Actions 为准。不要把 `gki/`、`out/`、`third_party/` 提交进仓库。

---

## 1. 设备

| 项 | 值 |
|---|---|
| 机型 | REDMI K90 |
| 代号 | `annibale` |
| 内部型号 | `2510DRK44C` |
| 平台 | `sun` / SM8750 |
| 官方内核 | `6.6.77-android15-8-g4a507830d890-ab13636293-4k` |
| Android | 16（SDK 36） |
| 页大小 | **4K**。不要编 `kernel_aarch64_16k` |

目标：AOSP GKI **6.6.77**（官方同代）+ 内置 SukiSU Ultra + KPM + SUSFS + `RFKILL=y` + ShirkNeko **默认 release** 对齐项。

不要：网上通用 GKI zip、16K、Xiaomi OSS 当主构建、ZRAM LZ4KD、BBG、默认 BBR、一加补丁、刷我们编的 `system_dlkm*.img`。

---

## 2. 版本必须钉死

| 组件 | 值 |
|---|---|
| manifest 分支 | `common-android15-6.6`（这是 git branch，可以 `repo init -b`） |
| common tag | `android15-6.6-2025-03_r15` |
| 该 tag 的 commit | `4a507830d890`（和官方 uname 里的 hash 一致） |
| 内核版本 | `6.6.77` |
| SukiSU | `https://github.com/SukiSU-Ultra/SukiSU-Ultra` 分支 **`builtin`**（验证时 `b1d534bc` / 40856） |
| SUSFS | `https://github.com/ShirkNeko/susfs4ksu.git` 分支 **`gki-android15-6.6`**（验证时 v2.2.0） |
| 构建目标 | 在 `gki/` 下：`tools/bazel run --lto=thin //common:kernel_aarch64_dist` |
| 并行 | 4 核约 15GB 内存用 `BUILD_JOBS=3`，thin LTO 大约 1–2 小时 |

`repo init -b android15-6.6-2025-03` 会失败：那是 tag 不是 branch。`scripts/01-sync-aosp-gki.sh` 已按「先 branch 再 pin tag」写好。

SukiSU/SUSFS 不必锁死某一个 commit，但分支不能错。换更新 commit 后补丁可能对不上，要重新打并验证。

---

## 3. 怎么编（按这个顺序）

工作根目录 `ROOT` = 本文件所在目录（clone 本仓库后的那一层，里面有 `BUILD-K90-GKI.md`、`scripts/`、`configs/`）。

新机器要求：

- x86_64 Linux，Debian / Ubuntu 22.04+（`00` 用 apt）
- 能访问 `android.googlesource.com` 和 GitHub
- 磁盘预留 **80GB+**（源码 + bazel 缓存 + 产物）
- 内存 **16GB** 比较稳，`BUILD_JOBS=3`、`LTO=thin`
- 完整 sync 大约 20–40GB，编一次大约 1–2 小时

### 3.1 同一台机器、树已经打过补丁，只重编

不要跑 `01` / `02` / `03`。先跑一遍 `04`（幂等），再编：

```bash
cd "$ROOT"
bash scripts/04-apply-shirkneko-defaults.sh
AOSP_DIST="$ROOT/out/aosp-release" BUILD_JOBS=3 LTO=thin \
  bash scripts/05-build-gki.sh aosp
bash scripts/06-pack-anykernel.sh
bash scripts/07-patch-kpm.sh
```

### 3.2 全新系统：clone 本仓库之后从零拉源码

```bash
cd "$ROOT"
sudo bash scripts/00-install-deps.sh
bash scripts/01-sync-aosp-gki.sh
bash scripts/02-apply-sukisu.sh aosp
bash scripts/03-apply-susfs.sh
bash scripts/04-apply-shirkneko-defaults.sh
AOSP_DIST="$ROOT/out/aosp-release" BUILD_JOBS=3 LTO=thin \
  bash scripts/05-build-gki.sh aosp
bash scripts/06-pack-anykernel.sh
bash scripts/07-patch-kpm.sh
```

顺序不能乱：`02` 把 SukiSU 停在 `main`，`03` 才切到 `builtin` 并打 SUSFS，`04` 才做 RFKILL 清单 / hide_stuff / 去 dirty。只跑 `02`+`03` 就编，**bazel 会在缺 `rfkill.ko` 时失败**，或者编出 WiFi/蓝牙仍坏的包。

### 3.3 绝对不要

- **不要对已经打过补丁的树再跑 `01-sync-aosp-gki.sh`。**  
  它会对 `gki/common` 执行 `git checkout --detach` 到干净 r15，本地 SUSFS / hide_stuff / defconfig 改动会被丢掉或 checkout 失败。
- 不要编 `//common:kernel_aarch64_16k`。
- 不要刷 `out/aosp-release/system_dlkm*.img`。只换 Image / boot。
- 不要用网上通用 6.6.x GKI，这台会闪屏。

---

## 4. 编之前用这张表核对

缺哪条补哪条，不要盲目重跑会改分支的脚本。

| 检查 | 期望 |
|---|---|
| `git -C gki/common log -1 --oneline` | 以 `4a507830d` 开头（工作区可以是脏的） |
| `awk '/^VERSION\|^PATCHLEVEL\|^SUBLEVEL/' gki/common/Makefile` | 6 / 6 / 77 |
| `gki/common/drivers/kernelsu` | 存在 |
| `git -C gki/common/KernelSU branch --show-current` | `builtin` |
| `gki/common/include/linux/susfs.h` | 存在 |
| `grep ^CONFIG_RFKILL= gki/common/arch/arm64/configs/gki_defconfig` | `CONFIG_RFKILL=y` |
| `grep rfkill.ko gki/common/modules.bzl` | **没有**输出 |
| `gki/common/build.config.gki` | `POST_DEFCONFIG_CMDS=""` |
| `gki/common/BUILD.bazel` 里 `"kernel_aarch64":` 那段 | **没有** `protected_exports_list` |
| `gki/build/kernel/kleaf/impl/stamp.bzl` | `echo '-g4a507830d890'`，不是 `echo '-maybe-dirty'` |
| `gki/common/fs/proc/task_mmu.c` | 有 `show_vma_header_prefix_fake` 和 `jit-zygote-cache` |

`04` 会把后几条自动补上。

---

## 5. 脚本实际做什么

| 脚本 | 做什么 | 不会做 |
|---|---|---|
| `00-install-deps.sh` | `apt-get` 装 git/repo/编译依赖。要用 **`sudo bash`**，脚本内部自己不 sudo | 不装 bazel（用 `gki/tools/bazel`） |
| `01-sync-aosp-gki.sh` | `repo init` 分支 `common-android15-6.6`，sync，再把 `common` detach 到 tag `android15-6.6-2025-03_r15` | **会重置 common** |
| `02-apply-sukisu.sh aosp` | `setup.sh` + checkout **`main`**，再把 `configs/sukisu.fragment` 合进 defconfig（含 `KSU`/`KPM`/`RFKILL=y`，也会写入 `KSU_MANUAL_SU`） | 没有 SUSFS；SukiSU 还停在 `main` |
| `03-apply-susfs.sh` | checkout SukiSU **`builtin`**，打 `susfs4ksu` 的 `50_add_susfs_in_gki-android15-6.6.patch`，追加 SUSFS defconfig，删掉 `KSU_MANUAL_SU`。有 `gki/common/.sukisu_susfs_applied` 就跳过 | 不含 hide_stuff、TTL、modules.bzl、stamp、protected_exports |
| `04-apply-shirkneko-defaults.sh` | **落地** RFKILL=y、删 `rfkill.ko`、关 check_defconfig、TTL/HL、去 protected_exports、去 maybe-dirty、hide_stuff。可重复跑 | 不开 ZRAM/BBG/默认 BBR |
| `05-build-gki.sh aosp` | 在 `gki/` 里 `tools/bazel run --lto=thin //common:kernel_aarch64_dist`，输出到 `AOSP_DIST`（默认 `out/aosp`） | **不再** merge fragment。AOSP 路径走 kleaf 自己的 clang，**不用** 脚本里的 `find_clang_bin`（那个只给 xiaomi make 用） |
| `06-pack-anykernel.sh` | WildKernels AK3 + 未压缩 `Image` | 不预打 KPM |
| `07-patch-kpm.sh` | Linux `kptools` + 管理器同款 `kpimg`（`-s 123`）补 `Image`，产出 `Image-kpm` / `boot-kpm.img` / `*-KPM-AnyKernel3.zip` | 不改未修补的 `Image` 和普通 AK3 zip；不打 `*-lz4` |

`05` 成功日志里应有：

```
-- SukiSU-Ultra: using SUSFS_INLINE_HOOK
-- KPM is enabled
-- SUSFS_VERSION: v2.2.0
```

产物目录里 **不应** 有 `rfkill.ko`。`System.map` 里应有 `rfkill_alloc`。

---

## 6. 为什么必须这样（不要改回去）

**通用 GKI 闪屏**  
网上 6.6.x / 16K / 带额外调度补丁的包，在这台 6.6.77 上会花屏。必须自己用 r15 编 4K。

**`RFKILL=y` 编进 Image**  
只 `fastboot boot` 自定义 Image 时，官方 `system_dlkm` 里的 `rfkill.ko` vermagic 对不上。`RFKILL=m` 时厂商 `cfg80211`/`btpower` 会 `Unknown symbol rfkill_*`，WiFi 和蓝牙一起挂。  
`RFKILL=y` 之后还要从 `modules.bzl` 删掉 `"net/rfkill/rfkill.ko",`，否则 bazel 报找不到该 ko。

编进去之后，开机日志里官方 ko 报 `exports duplicate symbol rfkill_alloc (owned by kernel)` 是正常的，不要再去装分区那份。

**SUSFS 必须 `builtin`**  
`main` 没有 SUSFS。`02` 之后一定要 `03`。

**关掉 check_defconfig**  
改了 `gki_defconfig` 以后，`gki/common/build.config.gki` 必须是 `POST_DEFCONFIG_CMDS=""`。`04` 会写。

**ShirkNeko 默认 release 对齐（`04` 做的）**  
hide_stuff、TTL/HL、去掉 `-maybe-dirty`、去掉 `kernel_aarch64` 的 `protected_exports_list`。  
他们默认 **不开** 的我们也不开：ZRAM LZ4KD、BBG、`CONFIG_DEFAULT_BBR=y`、一加补丁。  
官方 GKI 里已经有 `CONFIG_TCP_CONG_BBR=y`，默认拥塞算法保持 cubic。  
`AUTO_ADD_SUS_*` 会写入 defconfig；当前 `builtin` Kconfig 可能没有这些选项，写了会被忽略。

**hide_stuff 不能直接套官方 patch**  
`69_hide_stuff.patch` 基于旧 `task_mmu.c`，和现有 SUSFS 冲突。`scripts/lib/apply_hide_stuff.py` 是移植版：maps 里藏 `lineage` / `jit-zygote-cache`。

**不要刷 system_dlkm**  
厂商模块继续用机子上的 `vendor_dlkm`。

---

## 7. 产物

```
out/aosp-release/boot.img              ← 真机验证用这个（未压缩）
out/aosp-release/boot-kpm.img          ← 已打 KPM，同样 fastboot boot
out/aosp-release/boot-lz4.img          ← AOSP 也打，annibale 上不能引导
out/aosp-release/boot-gz.img
out/aosp-release/Image
out/aosp-release/Image.gz
out/aosp-release/Image.lz4
out/SukiSU-annibale-aosp-6.6.77-4k-SUSFS-REL-AnyKernel3.zip
```

不要和这些旧目录搞混：

| 目录 | 状态 |
|---|---|
| `out/aosp`、`out/aosp-nosusfs` | 早期无 SUSFS |
| `out/aosp-susfs` | 有 SUSFS，仍是 `RFKILL=m`，WiFi/蓝牙坏 |
| `out/aosp-rfkill` | WiFi/蓝牙已好，还没有 hide_stuff / 去 dirty |

---

## 8. 验收

```bash
fastboot boot "$ROOT/out/aosp-release/boot.img"
```

```text
uname -r
# 必须：6.6.77-android15-8-g4a507830d890-4k
# 不要：maybe-dirty、16k、6.6.57、更高 6.6.x

dmesg | grep -E 'Unknown symbol|susfs_init|qca_cld3|bt_power_probe'
# 不应有 rfkill_* Unknown symbol
# 应有 susfs is initialized
# 应有 qca_cld3 / bt_power_probe

getprop wlan.driver.status            # ok
getprop wifi.active.interface         # wlan0
getprop debug.device.bluetooth_state  # 1
```

用户侧：WiFi 能开能连，蓝牙能开，震动不是高频乱震，SukiSU 显示工作中。

长期再用 AnyKernel3 或 `fastboot flash boot`。先备份官方 `boot.img`。zip 还没在这台机上刷过，优先继续用未压缩 `boot.img` 验证。

---

## 9. 日志噪声（不要因此重编）

- `rfkill: exports duplicate symbol rfkill_alloc (owned by kernel)`：已经内置。
- 官方 `bluetooth.ko` / `hci_uart.ko` / `nfc.ko` 装失败：小米走 `btpower` + QTI HAL / `NxpDrv`。
- `regulatory.db` / `wlan_mac.bin` 找不到：厂商驱动用自己的 ini / persist。
- `poll HPWR_DISABLED failed after stopped play`：开机校准，震动仍可用。
- `KernelSU: target type nsfs does not exist`（cmd 16/17）：Android 16 上已知。

真坏了才会有：`cfg80211: Unknown symbol rfkill_*`、`btpower: Unknown symbol rfkill_*`、`Failed to load WiFi driver`、`BluetoothHci: error INITIALIZATION_ERROR`、`com.android.bluetooth` 反复 died。

---

## 10. 当前包里有什么

有：6.6.77 4K 同代 GKI、内置 SukiSU+KPM+ADB Root、SUSFS（`SUS_PATH=n`、`SUS_SU=n`）、`RFKILL` 内置、hide_stuff、TTL/HL、BBR 编进内核但默认 cubic、uname 无 dirty、去掉 protected exports。

没有：ZRAM 魔改、BBG、默认 BBR、一加补丁、小米未开源 DTS/驱动。

`configs/sukisu.fragment` 里的 `CONFIG_KSU_MANUAL_SU=y` 只对 `main` 有意义。`03` 切到 `builtin` 后会删掉。不要再加回去。

---

## 11. 仓库里不要放什么

构建以这个 GitHub 仓库 + Actions 为准。源码、clang、bazel、SUSFS、AnyKernel3 都在 runner 上按脚本重新拉。

不要提交：

| 路径 | 原因 |
|---|---|
| `gki/` | AOSP 整树，几十 GB，`01` 会重新 sync |
| `third_party/` | `03`/`06` 会重新 clone |
| `out/` | 产物，每次构建重新生成 |
| `logs/` | 本地日志，不是构建输入 |

## 12. 给下次的最短指令

1. 新机器：clone 本仓库，跑第 3.2 节（命令一行不要少）。
2. 旧机器已有打过补丁的 `gki/common`：跑第 3.1 节。
3. 用第 4 节表核对。
4. `fastboot boot "$ROOT/out/aosp-release/boot.img"`，按第 8 节验收。
5. 不要重跑 `01`，不要编 16K，不要刷 system_dlkm。
