#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="${ROOT}/gki"
BRANCH="${GKI_MANIFEST_BRANCH:-common-android15-6.6}"
# GKI_KERNEL_REF 优先（滚动分支 / 任意 committish）。否则钉 tag。
KERNEL_REF="${GKI_KERNEL_REF:-}"
KERNEL_TAG="${GKI_KERNEL_TAG:-android15-6.6-2025-03_r15}"
JOBS="${SYNC_JOBS:-4}"

mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

repo init --depth=1 \
  -u https://android.googlesource.com/kernel/manifest \
  -b "${BRANCH}"
repo sync -c --no-tags --fail-fast -j"${JOBS}"

if [[ -n "${KERNEL_REF}" ]]; then
  git -C common fetch --depth=1 \
    https://android.googlesource.com/kernel/common "${KERNEL_REF}"
else
  git -C common fetch --depth=1 \
    https://android.googlesource.com/kernel/common "tag" "${KERNEL_TAG}"
fi
git -C common checkout --detach FETCH_HEAD

awk '/^VERSION|^PATCHLEVEL|^SUBLEVEL/{print}' common/Makefile | paste -sd. -
git -C common log -1 --oneline
