#!/usr/bin/env bash
set -euo pipefail

# BakaSU（ReSukiSU，官方 v3.x 架构 + 原生 SUSFS 菜单）in-tree 集成 + SUSFS + Droidspaces。
#
# 关键配对事实（2026-10-24 预检 + dry-run 实证）：
# - BakaSU 原生自带 KSU_SUSFS Kconfig 菜单 → 不需要 susfs 的 10_ 驱动侧补丁。
# - susfs 内核侧 50_ 必须用 **preinit 合入之前**的版本（BakaSU 基座尚无官方
#   preinit API）：pin SUSFS_COMMIT=bd7d199a（10-12 版，0 hunk 失败）。
#   BakaSU sync-upstream 带入 preinit 后可解 pin（KSU_PREINIT=1 检测，届时改）。
# - Droidspaces：SYSVIPC 系移动 task_struct ABI（sysvsem/sysvshm），vendor 模块
#   CRC 失配 → bootloop（K90 真机 6 轮二分实证）。kABI 补丁把两字段挪进
#   ANDROID_KABI 预留位 6/7+8，布局不变。CFS_BANDWIDTH/CGROUP_PIDS 无补丁可救，
#   永久禁用。
#
# 覆盖输入：KSU_TAG/KSU_COMMIT（BakaSU tag/commit）、SUSFS_COMMIT。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_ROOT="${ROOT}/gki/common"
KSU="${KERNEL_ROOT}/KernelSU"
KSU_REPO="${KSU_REPO:-https://github.com/Baka-SU/BakaSU.git}"
KSU_TAG="${KSU_TAG:-}"
KSU_COMMIT="${KSU_COMMIT:-}"
SUSFS_DIR="${ROOT}/third_party/susfs4ksu"
SUSFS_BRANCH="gki-android15-6.6"
# preinit 合入前的最后一版 50_（对 BakaSU main dry-run 0 hunk 失败，2026-10-24）。
SUSFS_COMMIT="${SUSFS_COMMIT:-bd7d199ac87808001127e8a6d076832e2938cf0d}"
GKI_DEFCONFIG="${KERNEL_ROOT}/arch/arm64/configs/gki_defconfig"

if [ -n "${KSU_COMMIT}" ]; then
  ref="${KSU_COMMIT}"
elif [ -n "${KSU_TAG}" ]; then
  ref="${KSU_TAG}"
else
  ref="main"
fi

cd "${KERNEL_ROOT}"
if [ ! -d KernelSU ]; then
  if ! git clone --depth=1 --branch "${ref}" "${KSU_REPO}" KernelSU; then
    rm -rf KernelSU
    git clone --filter=blob:none "${KSU_REPO}" KernelSU
  fi
fi
git -C KernelSU fetch --depth=1 origin "${ref}"
git -C KernelSU checkout -q --detach FETCH_HEAD
git -C KernelSU reset --hard -q HEAD
KSU_SHA="$(git -C KernelSU rev-parse --short HEAD)"
echo "[+] BakaSU integrated (${ref} @ ${KSU_SHA})"

# susfs 内核侧（50_ + fs/include），pin 到与 BakaSU 基座配套的 commit。
git clone --depth=1 --branch "${SUSFS_BRANCH}" \
  https://github.com/ShirkNeko/susfs4ksu.git "${SUSFS_DIR}"
if [ "$(git -C "${SUSFS_DIR}" rev-parse HEAD)" != "${SUSFS_COMMIT}" ]; then
  git -C "${SUSFS_DIR}" fetch --depth=1 origin "${SUSFS_COMMIT}"
  git -C "${SUSFS_DIR}" checkout -q --detach FETCH_HEAD
fi
echo "[+] susfs4ksu @ $(git -C "${SUSFS_DIR}" rev-parse --short HEAD)"

# 驱动挂进 GKI 树（官方 setup.sh 同构）。
DRIVER_DIR="${KERNEL_ROOT}/drivers"
ln -sf "$(realpath --relative-to="${DRIVER_DIR}" "${KSU}/kernel")" "${DRIVER_DIR}/kernelsu"
grep -q "kernelsu" "${DRIVER_DIR}/Makefile" \
  || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "${DRIVER_DIR}/Makefile"
grep -q 'source "drivers/kernelsu/Kconfig"' "${DRIVER_DIR}/Kconfig" \
  || sed -i '/endmenu/i\source "drivers/kernelsu/Kconfig"' "${DRIVER_DIR}/Kconfig"

# Droidspaces fragment → defconfig。
FRAGMENT="${ROOT}/configs/bakasu.fragment"
while IFS= read -r line; do
  [[ -z "${line}" || "${line}" =~ ^# ]] && continue
  key="${line%%=*}"
  if grep -qE "^${key}=" "${GKI_DEFCONFIG}"; then
    sed -i "s|^${key}=.*|${line}|" "${GKI_DEFCONFIG}"
  elif grep -qE "^# ${key} is not set" "${GKI_DEFCONFIG}"; then
    sed -i "s|^# ${key} is not set|${line}|" "${GKI_DEFCONFIG}"
  else
    printf '\n%s\n' "${line}" >> "${GKI_DEFCONFIG}"
  fi
done < "${FRAGMENT}"

# 内核侧 SUSFS：fs/include 覆盖 + 50_（干净打上，失败即中止——预检 0 失败）。
cp -a "${SUSFS_DIR}/kernel_patches/fs/." "${KERNEL_ROOT}/fs/"
cp -a "${SUSFS_DIR}/kernel_patches/include/linux/." "${KERNEL_ROOT}/include/linux/"
cd "${KERNEL_ROOT}"
patch -p1 --no-backup-if-mismatch \
  < "${SUSFS_DIR}/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch"

# Droidspaces kABI 补丁（打在 GKI 树 sched.h；上下文 = AOSP r15 原味）。
patch -p1 --forward --no-backup-if-mismatch \
  < "${ROOT}/configs/sysvipc-kabi-6_7_8.patch"

# SUSFS 菜单：BakaSU 原生（10 项，键名与 SukiSU builtin 同构）。
# 取值沿用 K90 真机验证过的组合（SUS_PATH=n）。官方 Kconfig 无
# MANUAL_SU/ADBROOT，不要写。
cat >> "${GKI_DEFCONFIG}" <<'EOF'

# === SUSFS (BakaSU 原生菜单) ===
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=n
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG_TMPFS_XATTR=y
CONFIG_TMPFS_POSIX_ACL=y
EOF
