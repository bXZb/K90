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

# 月度清单常把 kernel/common 钉在 android15-6.6-YYYY-MM。
# AOSP 之后会把这个 heads 挪到 deprecated/，repo sync 会报 couldn't find remote ref。
MANIFEST="${WORKDIR}/.repo/manifests/default.xml"
if [[ -f "${MANIFEST}" ]]; then
  common_rev="$(
    python3 - "${MANIFEST}" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
for pat in (
    r'path="common"[^>]*revision="([^"]+)"',
    r'name="kernel/common"[^>]*revision="([^"]+)"',
    r'revision="([^"]+)"[^>]*path="common"',
    r'revision="([^"]+)"[^>]*name="kernel/common"',
):
    m = re.search(pat, text)
    if m:
        print(m.group(1))
        break
PY
  )"
  if [[ -n "${common_rev}" && "${common_rev}" != deprecated/* && "${common_rev}" != refs/* ]]; then
    if ! git ls-remote --exit-code --heads \
        https://android.googlesource.com/kernel/common "${common_rev}" >/dev/null 2>&1; then
      if git ls-remote --exit-code --heads \
          https://android.googlesource.com/kernel/common "deprecated/${common_rev}" >/dev/null 2>&1; then
        echo "rewrite kernel/common ${common_rev} -> deprecated/${common_rev}"
        python3 - "${MANIFEST}" "${common_rev}" <<'PY'
import sys
path, old = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
open(path, "w", encoding="utf-8").write(
    text.replace(f'revision="{old}"', f'revision="deprecated/{old}"')
)
PY
      fi
    fi
  fi
fi

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
