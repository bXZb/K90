#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_ROOT="${ROOT}/gki/common"

cd "${KERNEL_ROOT}"
curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" \
  | bash -s main

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
