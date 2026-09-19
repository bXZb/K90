#!/usr/bin/env bash
set -euo pipefail

# KSU_FLAVOR=builtin    (默认, 已验证) 上游 setup.sh + 03 切 builtin 分支
# KSU_FLAVOR=main-susfs (实验)        上游 main pin + 03 打上游 10_ 补丁 + K90 fixup
#                      (main@7755cdb3 + susfs4ksu@9d9464f19 的
#                      10_enable_susfs_for_ksu.patch + configs/sukisu-main-k90-fixup.patch)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_ROOT="${ROOT}/gki/common"
KSU_FLAVOR="${KSU_FLAVOR:-builtin}"

cd "${KERNEL_ROOT}"

case "${KSU_FLAVOR}" in
  builtin)
    curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" \
      | bash -s main
    ;;
  main-susfs)
    # 上游 main，pin 固定 commit；10_/fixup 两个驱动补丁在 03 打（那里才有 susfs4ksu 克隆）。
    KSU_REPO="${KSU_REPO:-https://github.com/SukiSU-Ultra/SukiSU-Ultra.git}"
    KSU_COMMIT="${KSU_COMMIT:-7755cdb36f63945f286d7b1cab662b42b18f2789}"
    test -d KernelSU || git clone "${KSU_REPO}" KernelSU
    git -C KernelSU checkout -q --detach "${KSU_COMMIT}"
    # 与上游 setup.sh 等价的驱动集成。
    DRIVER_DIR="${KERNEL_ROOT}/drivers"
    ln -sf "$(realpath --relative-to="${DRIVER_DIR}" "${KERNEL_ROOT}/KernelSU/kernel")" "${DRIVER_DIR}/kernelsu"
    grep -q "kernelsu" "${DRIVER_DIR}/Makefile" \
      || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "${DRIVER_DIR}/Makefile"
    grep -q 'source "drivers/kernelsu/Kconfig"' "${DRIVER_DIR}/Kconfig" \
      || sed -i '/endmenu/i\source "drivers/kernelsu/Kconfig"' "${DRIVER_DIR}/Kconfig"
    echo "[+] SukiSU main @ ${KSU_COMMIT} integrated"
    ;;
  *)
    echo "unknown KSU_FLAVOR: ${KSU_FLAVOR} (builtin | main-susfs)" >&2
    exit 1
    ;;
esac

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
