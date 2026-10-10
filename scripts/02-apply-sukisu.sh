#!/usr/bin/env bash
set -euo pipefail

# KSU_FLAVOR=builtin (默认, 已验证) 克隆 builtin，补 #974 缺口，打 50_，打开 SUSFS
# KSU_FLAVOR=tag     检出官方 tag（默认 = SukiSU-Ultra 仓库最新 tag；KSU_TAG / KSU_COMMIT 可改）
#                    官方 tag 没有 SUSFS 驱动菜单，50_ 的 ifdefs 保持关闭
#
# 两种 flavor 同构：克隆上游 + 驱动集成（symlink/Makefile/Kconfig）+ GKI 侧 50_。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/ksu_zip_prefix.sh
. "${ROOT}/scripts/lib/ksu_zip_prefix.sh"

KERNEL_ROOT="${ROOT}/gki/common"
KSU="${KERNEL_ROOT}/KernelSU"
KSU_FLAVOR="${KSU_FLAVOR:-builtin}"
KSU_REPO="${KSU_REPO:-https://github.com/SukiSU-Ultra/SukiSU-Ultra.git}"
KSU_TAG="${KSU_TAG:-}"
KSU_COMMIT="${KSU_COMMIT:-}"
SUSFS_DIR="${ROOT}/third_party/susfs4ksu"
SUSFS_BRANCH="gki-android15-6.6"

case "${KSU_FLAVOR}" in
  builtin) ;;
  tag) ;;
  *)
    echo "unknown KSU_FLAVOR: ${KSU_FLAVOR} (builtin | tag)" >&2
    exit 1
    ;;
esac

cd "${KERNEL_ROOT}"
if [ "${KSU_FLAVOR}" = "tag" ]; then
  if [ -n "${KSU_COMMIT}" ]; then
    ref="${KSU_COMMIT}"
  elif [ -n "${KSU_TAG}" ]; then
    ref="${KSU_TAG}"
  else
    KSU_TAG="$(ksu_latest_tag "${KSU_REPO}")"
    ref="${KSU_TAG}"
    echo "[+] KSU_TAG empty; using latest ${KSU_TAG}"
  fi
fi

if [ ! -d KernelSU ]; then
  if [ "${KSU_FLAVOR}" = "tag" ]; then
    if ! git clone --depth=1 --branch "${ref}" "${KSU_REPO}" KernelSU; then
      rm -rf KernelSU
      git clone --filter=blob:none "${KSU_REPO}" KernelSU
    fi
  else
    git clone --branch builtin "${KSU_REPO}" KernelSU
  fi
fi

if [ "${KSU_FLAVOR}" = "tag" ]; then
  git -C KernelSU fetch --depth=1 origin "${ref}"
  git -C KernelSU checkout -q --detach FETCH_HEAD
  if [ -z "${KSU_TAG}" ]; then
    KSU_TAG="$(git -C KernelSU describe --tags --exact-match HEAD 2>/dev/null || printf '%s' "${ref}")"
  fi
  ksu_persist_tag
else
  git -C KernelSU fetch origin builtin
  git -C KernelSU checkout -B builtin origin/builtin
  # SukiSU-Ultra#974 尚未合入：缺 arch.h、EVENT_SERVICES，rules.c 里重复声明。
  # 上游已有则跳过。post-execveat 已在 70fa0e09 落地，不再打 stub。
  # 官方管理器不主动 reboot 探测，开机要扫一次已装 APK 才能注入 [ksu_driver]。
  if [ ! -f "${KSU}/kernel/arch.h" ]; then
    cp "${ROOT}/configs/builtin-arch.h" "${KSU}/kernel/arch.h"
  fi
  if grep -q 'struct selinux_policy \*pol, \*old_pol = selinux_state.policy;' \
    "${KSU}/kernel/selinux/rules.c"; then
    patch -p1 --forward --fuzz=3 -d "${KSU}" \
      < "${ROOT}/configs/builtin-selinux-redecl.patch"
  fi
  if grep -q 'EVENT_SERVICES' "${KSU}/kernel/supercall/dispatch.c" && \
     ! grep -q 'EVENT_SERVICES' "${KSU}/kernel/include/uapi/supercall.h"; then
    patch -p1 --forward --fuzz=3 -d "${KSU}" \
      < "${ROOT}/configs/builtin-event-services.patch"
  fi
  # 42d7fda 管理器只认 [ksu_driver]，开机不扫已装 APK 就永远不会注入 fd。
  if ! grep -q 'track_throne(false);' "${KSU}/kernel/runtime/ksud.c"; then
    patch -p1 --forward --fuzz=3 -d "${KSU}" \
      < "${ROOT}/configs/builtin-crown-manager-on-boot.patch"
  fi
fi

DRIVER_DIR="${KERNEL_ROOT}/drivers"
ln -sf "$(realpath --relative-to="${DRIVER_DIR}" "${KERNEL_ROOT}/KernelSU/kernel")" "${DRIVER_DIR}/kernelsu"
grep -q "kernelsu" "${DRIVER_DIR}/Makefile" \
  || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "${DRIVER_DIR}/Makefile"
grep -q 'source "drivers/kernelsu/Kconfig"' "${DRIVER_DIR}/Kconfig" \
  || sed -i '/endmenu/i\source "drivers/kernelsu/Kconfig"' "${DRIVER_DIR}/Kconfig"

ksu_rev="$(git -C KernelSU rev-parse --short HEAD)"
if [ "${KSU_FLAVOR}" = "tag" ]; then
  echo "[+] SukiSU integrated (tag @ ${ksu_rev} / ${KSU_COMMIT:-${KSU_TAG}})"
else
  echo "[+] SukiSU integrated (builtin @ ${ksu_rev})"
fi

FRAGMENT="${ROOT}/configs/sukisu.fragment"
GKI_DEFCONFIG="${KERNEL_ROOT}/arch/arm64/configs/gki_defconfig"
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

git clone --depth=1 --branch "${SUSFS_BRANCH}" \
  https://github.com/ShirkNeko/susfs4ksu.git "${SUSFS_DIR}"

cp -a "${SUSFS_DIR}/kernel_patches/fs/." "${KERNEL_ROOT}/fs/"
cp -a "${SUSFS_DIR}/kernel_patches/include/linux/." "${KERNEL_ROOT}/include/linux/"

cd "${KERNEL_ROOT}"
patch -p1 --forward --fuzz=3 \
  < "${SUSFS_DIR}/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch"

if [ "${KSU_FLAVOR}" = "builtin" ]; then
  # builtin Kconfig 没有这三个选项，写了也没意义。
  sed -i \
    -e '/^CONFIG_KSU_MANUAL_SU=/d' \
    -e '/^CONFIG_KSU_DISABLE_MANAGER=/d' \
    -e '/^CONFIG_KSU_DISABLE_POLICY=/d' \
    "${GKI_DEFCONFIG}"
  cat >> "${GKI_DEFCONFIG}" <<'EOF'

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
    "${GKI_DEFCONFIG}"
  cat >> "${GKI_DEFCONFIG}" <<'EOF'

# CONFIG_KSU_MANUAL_SU is not set
CONFIG_TMPFS_XATTR=y
CONFIG_TMPFS_POSIX_ACL=y
EOF
fi
