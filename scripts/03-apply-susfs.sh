#!/usr/bin/env bash
set -euo pipefail

# KSU_FLAVOR=builtin    (默认) 切 SukiSU builtin 分支；susfs4ksu 跟踪分支 (--depth=1)
# KSU_FLAVOR=main-susfs (实验) 不切分支（02 已装 vendored main+10_）；susfs4ksu pin 固定 commit

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMON="${ROOT}/gki/common"
KSU="${COMMON}/KernelSU"
SUSFS_DIR="${ROOT}/third_party/susfs4ksu"
SUSFS_BRANCH="gki-android15-6.6"
KSU_FLAVOR="${KSU_FLAVOR:-builtin}"

case "${KSU_FLAVOR}" in
  builtin)
    git -C "${KSU}" fetch origin builtin
    git -C "${KSU}" checkout -B builtin origin/builtin
    SUSFS_COMMIT="${SUSFS_COMMIT:-}"
    ;;
  main-susfs)
    # 与 fork susfs-main-k90 分支里的 10_ 补丁同源的 susfs4ksu 提交。
    SUSFS_COMMIT="${SUSFS_COMMIT:-9d9464f191b2d846590ac4d1b52e123df135c401}"
    ;;
  *)
    echo "unknown KSU_FLAVOR: ${KSU_FLAVOR} (builtin | main-susfs)" >&2
    exit 1
    ;;
esac

if [ -n "${SUSFS_COMMIT}" ]; then
  # 需要 checkout 固定 commit，不能浅克隆。
  git clone --branch "${SUSFS_BRANCH}" \
    https://github.com/ShirkNeko/susfs4ksu.git "${SUSFS_DIR}"
  git -C "${SUSFS_DIR}" checkout --detach "${SUSFS_COMMIT}"
else
  git clone --depth=1 --branch "${SUSFS_BRANCH}" \
    https://github.com/ShirkNeko/susfs4ksu.git "${SUSFS_DIR}"
fi

cp -a "${SUSFS_DIR}/kernel_patches/fs/." "${COMMON}/fs/"
cp -a "${SUSFS_DIR}/kernel_patches/include/linux/." "${COMMON}/include/linux/"

cd "${COMMON}"
patch -p1 --forward --fuzz=3 \
  < "${SUSFS_DIR}/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch"

DEFCONFIG="${COMMON}/arch/arm64/configs/gki_defconfig"
if [ "${KSU_FLAVOR}" = "builtin" ]; then
  # builtin Kconfig 没有这三个选项，写了也没意义。
  sed -i \
    -e '/^CONFIG_KSU_MANUAL_SU=/d' \
    -e '/^CONFIG_KSU_DISABLE_MANAGER=/d' \
    -e '/^CONFIG_KSU_DISABLE_POLICY=/d' \
    "${DEFCONFIG}"
else
  # main 的 KSU_MANUAL_SU 默认 y；与 builtin 流程对齐，显式关闭 manual su。
  sed -i 's/^CONFIG_KSU_MANUAL_SU=y/# CONFIG_KSU_MANUAL_SU is not set/' "${DEFCONFIG}"
  sed -i \
    -e '/^CONFIG_KSU_DISABLE_MANAGER=/d' \
    -e '/^CONFIG_KSU_DISABLE_POLICY=/d' \
    "${DEFCONFIG}"
fi

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
