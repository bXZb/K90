#!/usr/bin/env bash
# Fetch Xiaomi annibale-w-oss (K90 / POCO F8 Pro).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${ROOT}/xiaomi"
BRANCH="${XIAOMI_BRANCH:-annibale-w-oss}"
URL="${XIAOMI_URL:-https://github.com/MiCode/Xiaomi_Kernel_OpenSource.git}"

if [[ -d "${DEST}/.git" ]]; then
  echo "[=] xiaomi tree exists, fetching ${BRANCH}"
  git -C "${DEST}" fetch --depth=1 origin "${BRANCH}"
  git -C "${DEST}" checkout -f FETCH_HEAD
else
  echo "[+] cloning ${URL} (${BRANCH})"
  git clone --depth=1 --branch "${BRANCH}" "${URL}" "${DEST}"
fi

echo "[+] Xiaomi kernel version:"
awk '/^VERSION|^PATCHLEVEL|^SUBLEVEL/{print}' "${DEST}/Makefile" | paste -sd. -

echo "[+] Xiaomi tree ready: ${DEST}"
