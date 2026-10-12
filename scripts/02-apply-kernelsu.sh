#!/usr/bin/env bash
set -euo pipefail

# 官方 KernelSU（tiann/KernelSU）in-tree 集成 + SUSFS。
# 这是 susfs4ksu README 明示的标准组合：官方 KSU tag + 10_（驱动侧）+ 50_（内核侧）。
#   KSU_TAG / KSU_COMMIT：指定 tag 或 commit；空 = 官方仓库最新 tag。
# 流程：clone 官方 KernelSU → 10_ 补丁打进驱动 → symlink/Makefile/Kconfig 挂接
#      → defconfig fragment → susfs fs/include + 50_ 补丁 → 打开 SUSFS 菜单。
# 官方 v3.x kernel/ 目录同时带 Kbuild（in-tree）与 Makefile（LKM 独立构建），
# in-tree 走 Kbuild，集成方式与官方 setup.sh 同构。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/ksu_zip_prefix.sh
. "${ROOT}/scripts/lib/ksu_zip_prefix.sh"

KERNEL_ROOT="${ROOT}/gki/common"
KSU="${KERNEL_ROOT}/KernelSU"
KSU_REPO="${KSU_REPO:-https://github.com/tiann/KernelSU.git}"
KSU_TAG="${KSU_TAG:-}"
KSU_COMMIT="${KSU_COMMIT:-}"
SUSFS_DIR="${ROOT}/third_party/susfs4ksu"
SUSFS_BRANCH="gki-android15-6.6"
GKI_DEFCONFIG="${KERNEL_ROOT}/arch/arm64/configs/gki_defconfig"

if [ -n "${KSU_COMMIT}" ]; then
  ref="${KSU_COMMIT}"
elif [ -n "${KSU_TAG}" ]; then
  ref="${KSU_TAG}"
else
  KSU_TAG="$(ksu_latest_tag "${KSU_REPO}")"
  ref="${KSU_TAG}"
  echo "[+] KSU_TAG empty; using latest ${KSU_TAG}"
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
# 本地重跑时清掉上次 10_/手工改动，保证 patch 总是打在干净 tag 上。
git -C KernelSU reset --hard -q HEAD
if [ -z "${KSU_TAG}" ]; then
  KSU_TAG="$(git -C KernelSU describe --tags --exact-match HEAD 2>/dev/null || printf '%s' "${ref}")"
fi
ksu_persist_tag

# susfs4ksu：gki-android15-6.6 分支无 tag，用移动 HEAD（与 SukiSU 线一致裸跟随）。
git clone --depth=1 --branch "${SUSFS_BRANCH}" \
  https://github.com/ShirkNeko/susfs4ksu.git "${SUSFS_DIR}"

# 10_：驱动侧 SUSFS。susfs4ksu 以官方 KSU 为基准维护，此处应当干净打上；
# 有 hunk 失败即中止（上游漂移需人工对齐，不要带病构建）。
cd "${KSU}"
patch -p1 --no-backup-if-mismatch \
  < "${SUSFS_DIR}/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
cd "${KERNEL_ROOT}"

# 驱动挂进 GKI 树（与官方 setup.sh 同构：相对 symlink + Makefile 追加 + Kconfig endmenu 前）。
DRIVER_DIR="${KERNEL_ROOT}/drivers"
ln -sf "$(realpath --relative-to="${DRIVER_DIR}" "${KSU}/kernel")" "${DRIVER_DIR}/kernelsu"
grep -q "kernelsu" "${DRIVER_DIR}/Makefile" \
  || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "${DRIVER_DIR}/Makefile"
grep -q 'source "drivers/kernelsu/Kconfig"' "${DRIVER_DIR}/Kconfig" \
  || sed -i '/endmenu/i\source "drivers/kernelsu/Kconfig"' "${DRIVER_DIR}/Kconfig"

ksu_rev="$(git -C KernelSU rev-parse --short HEAD)"
echo "[+] KernelSU integrated (${KSU_COMMIT:-${KSU_TAG}} @ ${ksu_rev})"

FRAGMENT="${ROOT}/configs/kernelsu.fragment"
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

# 内核侧 SUSFS：fs/ 与 include/linux/ 直接覆盖，50_ 打 GKI 树。
cp -a "${SUSFS_DIR}/kernel_patches/fs/." "${KERNEL_ROOT}/fs/"
cp -a "${SUSFS_DIR}/kernel_patches/include/linux/." "${KERNEL_ROOT}/include/linux/"

cd "${KERNEL_ROOT}"
patch -p1 --forward --fuzz=3 \
  < "${SUSFS_DIR}/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch"

# 10_ Kconfig 菜单与 SukiSU builtin 同名同构（默认全 y）；显式写出防上游默认漂移。
# 取值对齐已验证的 builtin 配置（SUS_PATH=n、SUS_SU 无此键勿加）。
# 官方 Kconfig 无 KSU_MANUAL_SU / KSU_FEATURE_ADBROOT，不要写。
cat >> "${GKI_DEFCONFIG}" <<'EOF'

# === SUSFS (官方 KernelSU + 10_ Kconfig) ===
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
