#!/usr/bin/env bash
set -euo pipefail

# KSU_FLAVOR=builtin (默认, 已验证) 克隆上游默认分支，03 再切 builtin
# KSU_FLAVOR=main    检出官方 tag（默认 v4.2.0；KSU_TAG / KSU_COMMIT 可改）
#
# 两种 flavor 同构：克隆上游 + 驱动集成（symlink/Makefile/Kconfig）。
# 官方 tag 的驱动没有 SUSFS Kconfig，03 不再打 10_ / K90 fixup。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_ROOT="${ROOT}/gki/common"
KSU_FLAVOR="${KSU_FLAVOR:-builtin}"
KSU_REPO="${KSU_REPO:-https://github.com/SukiSU-Ultra/SukiSU-Ultra.git}"
KSU_TAG="${KSU_TAG:-v4.2.0}"
KSU_COMMIT="${KSU_COMMIT:-}"

case "${KSU_FLAVOR}" in
  builtin) ;;
  main|main-susfs) KSU_FLAVOR=main ;;
  *)
    echo "unknown KSU_FLAVOR: ${KSU_FLAVOR} (builtin | main)" >&2
    exit 1
    ;;
esac

cd "${KERNEL_ROOT}"
if [ ! -d KernelSU ]; then
  if [ "${KSU_FLAVOR}" = "main" ]; then
    ref="${KSU_COMMIT:-${KSU_TAG}}"
    if ! git clone --depth=1 --branch "${ref}" "${KSU_REPO}" KernelSU; then
      rm -rf KernelSU
      git clone --filter=blob:none "${KSU_REPO}" KernelSU
    fi
  else
    git clone "${KSU_REPO}" KernelSU
  fi
fi

if [ "${KSU_FLAVOR}" = "main" ]; then
  ref="${KSU_COMMIT:-${KSU_TAG}}"
  git -C KernelSU fetch --depth=1 origin "${ref}"
  git -C KernelSU checkout -q --detach FETCH_HEAD
fi

DRIVER_DIR="${KERNEL_ROOT}/drivers"
ln -sf "$(realpath --relative-to="${DRIVER_DIR}" "${KERNEL_ROOT}/KernelSU/kernel")" "${DRIVER_DIR}/kernelsu"
grep -q "kernelsu" "${DRIVER_DIR}/Makefile" \
  || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "${DRIVER_DIR}/Makefile"
grep -q 'source "drivers/kernelsu/Kconfig"' "${DRIVER_DIR}/Kconfig" \
  || sed -i '/endmenu/i\source "drivers/kernelsu/Kconfig"' "${DRIVER_DIR}/Kconfig"

ksu_rev="$(git -C KernelSU rev-parse --short HEAD)"
if [ "${KSU_FLAVOR}" = "main" ]; then
  echo "[+] SukiSU integrated (main @ ${ksu_rev} / ${KSU_COMMIT:-${KSU_TAG}})"
else
  echo "[+] SukiSU integrated (builtin prep @ ${ksu_rev}; 03 switches to builtin)"
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
