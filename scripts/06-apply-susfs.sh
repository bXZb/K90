#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMON="${ROOT}/gki/common"
KSU="${COMMON}/KernelSU"
SUSFS_DIR="${ROOT}/third_party/susfs4ksu"
SUSFS_BRANCH="gki-android15-6.6"

git -C "${KSU}" fetch origin builtin
git -C "${KSU}" checkout -B builtin origin/builtin

git clone --depth=1 --branch "${SUSFS_BRANCH}" \
  https://github.com/ShirkNeko/susfs4ksu.git "${SUSFS_DIR}"

cp -a "${SUSFS_DIR}/kernel_patches/fs/." "${COMMON}/fs/"
cp -a "${SUSFS_DIR}/kernel_patches/include/linux/." "${COMMON}/include/linux/"

cd "${COMMON}"
patch -p1 --forward --fuzz=3 \
  < "${SUSFS_DIR}/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch"

DEFCONFIG="${COMMON}/arch/arm64/configs/gki_defconfig"
sed -i \
  -e '/^CONFIG_KSU_MANUAL_SU=/d' \
  -e '/^CONFIG_KSU_DISABLE_MANAGER=/d' \
  -e '/^CONFIG_KSU_DISABLE_POLICY=/d' \
  "${DEFCONFIG}"

cat >> "${DEFCONFIG}" <<'EOF'

# === SUSFS only ===
CONFIG_KSU_FEATURE_ADBROOT=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=n
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG_KSU_SUSFS_SUS_SU=n
CONFIG_TMPFS_XATTR=y
CONFIG_TMPFS_POSIX_ACL=y
EOF
