#!/usr/bin/env bash
set -euo pipefail

# KSU_FLAVOR=builtin (默认) 切 SukiSU builtin 分支，打 stub + 50_，打开 SUSFS Kconfig
# KSU_FLAVOR=tag     02 已检出官方 tag；只打 GKI 侧 50_（hide_stuff 需要）
#                    官方 tag 没有 SUSFS 驱动菜单，50_ 的 ifdefs 保持关闭

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
    # SukiSU-Ultra#974: kernel_includes.h 引用 arch.h，builtin 还没提交该文件。
    if [ ! -f "${KSU}/kernel/arch.h" ]; then
      cp "${ROOT}/configs/builtin-arch.h" "${KSU}/kernel/arch.h"
    fi
    # apply_kernelsu_rules() 函数作用域已声明 pol/old_pol，内层再声明一次会被
    # GKI CONFIG_WERROR 判为重定义。#974 合进 builtin 后这行会消失，跳过即可。
    if grep -q 'struct selinux_policy \*pol, \*old_pol = selinux_state.policy;' \
      "${KSU}/kernel/selinux/rules.c"; then
      patch -p1 --forward --fuzz=3 -d "${KSU}" \
        < "${ROOT}/configs/builtin-selinux-redecl.patch"
    fi
    # susfs4ksu d4ea3dd76（09-12）起，50_ 补丁引用 ksu_handle_post_execveat_sucompat。
    # builtin 在 pre-execve hook 已完成授权，打 no-op stub 满足内核侧引用即可。
    patch -p1 --forward --fuzz=3 -d "${KSU}" \
      < "${ROOT}/configs/builtin-post-execveat-stub.patch"
    ;;
  tag) ;;
  *)
    echo "unknown KSU_FLAVOR: ${KSU_FLAVOR} (builtin | tag)" >&2
    exit 1
    ;;
esac

git clone --depth=1 --branch "${SUSFS_BRANCH}" \
  https://github.com/ShirkNeko/susfs4ksu.git "${SUSFS_DIR}"

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
  cat >> "${DEFCONFIG}" <<'EOF'

# === SUSFS (builtin Kconfig) ===
# TRY_UMOUNT/AUTO_ADD_*/SUS_SU 等历史键不存在，写了会被静默忽略，勿加回。
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
else
  # 官方 tag Kconfig 有 MANUAL_SU 且默认 y；与 builtin 对齐后关掉。
  # 没有 SUSFS 菜单，不要写 CONFIG_KSU_SUSFS*（50_ 的 GKI 代码会因此保持关闭）。
  sed -i \
    -e '/^CONFIG_KSU_MANUAL_SU=/d' \
    -e '/^# CONFIG_KSU_MANUAL_SU is not set/d' \
    -e '/^CONFIG_KSU_DISABLE_MANAGER=/d' \
    -e '/^CONFIG_KSU_DISABLE_POLICY=/d' \
    "${DEFCONFIG}"
  cat >> "${DEFCONFIG}" <<'EOF'

# CONFIG_KSU_MANUAL_SU is not set
CONFIG_TMPFS_XATTR=y
CONFIG_TMPFS_POSIX_ACL=y
EOF
fi
