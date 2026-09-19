#!/usr/bin/env bash
set -euo pipefail

# KSU_FLAVOR=builtin    (默认) 切 SukiSU builtin 分支；susfs4ksu 跟踪分支 (--depth=1)
# KSU_FLAVOR=main-susfs (实验) 不切分支（02 已装上游 main pin）；susfs4ksu pin 固定 commit，
#                       驱动侧打上游 10_ + configs/sukisu-main-k90-fixup.patch

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
    # susfs4ksu d4ea3dd76（09-12）起，50_ 补丁引用 ksu_handle_post_execveat_sucompat，
    # 该符号只有 main+10_ 驱动提供。builtin 在 pre-execve hook 已完成授权，
    # 打 no-op stub 满足内核侧引用即可。若上游改动 sucompat.c 导致补丁失配，需重生成。
    patch -p1 --forward --fuzz=3 -d "${KSU}" \
      < "${ROOT}/configs/builtin-post-execveat-stub.patch"
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

# main-susfs：驱动侧再打上游 10_（拆 syscall-hook、装 SUSFS inline hook）
# + K90 fixup（3 处修正：init.c 手工移植、保留 symbol_resolver、selinux_hide
#   的 -Werror 写法；详见 patch 头部说明）。
if [ "${KSU_FLAVOR}" = "main-susfs" ]; then
  # 10_ 的 core/init.c 有 3 个 hunk 与 main HEAD 漂移，预期失败并落 .rej；
  # 放行后校验拒绝范围，再由 fixup 提供这三处的正确内容。
  patch -p1 --forward --fuzz=3 -d "${KSU}" \
    < "${SUSFS_DIR}/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" \
    || true
  bad_rejs=$(find "${KSU}" -name "*.rej" ! -name "init.c.rej")
  if [ -n "${bad_rejs}" ]; then
    echo "10_ 出现预期之外的 .rej（上游补丁或 main 又漂移了）：" >&2
    echo "${bad_rejs}" >&2
    exit 1
  fi
  find "${KSU}" -name "*.rej" -delete
  find "${KSU}" -name "*.orig" -delete
  patch -p1 --forward -d "${KSU}" \
    < "${ROOT}/configs/sukisu-main-k90-fixup.patch"
fi

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
# 注：键须与 Kconfig 菜单真实存在（builtin 与 10_ 的菜单一致，10 项）；
# TRY_UMOUNT/AUTO_ADD_*/SUS_SU 等历史键两侧都不存在，写了会被静默忽略，勿加回。
CONFIG_KSU_FEATURE_ADBROOT=y
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
