#!/usr/bin/env bash
# Shared KernelSU tag / artifact prefix. Sourced by 02, 05.
# 本分支只构建官方 KernelSU（tiann/KernelSU）单一形态。

ksu_latest_tag() {
  local repo="${1:-${KSU_REPO:-https://github.com/tiann/KernelSU.git}}"
  local tag
  tag="$(
    git ls-remote --tags --sort=-version:refname "${repo}" \
      | awk '{print $2}' \
      | sed 's@^refs/tags/@@' \
      | grep -v '\^{}$' \
      | grep -E '^v?[0-9]' \
      | head -n1
  )"
  if [ -z "${tag}" ]; then
    echo "could not resolve latest KernelSU tag from ${repo}" >&2
    return 1
  fi
  printf '%s' "${tag}"
}

ksu_stamp_file() {
  printf '%s/out/.ksu-tag' "${ROOT:?}"
}

ksu_persist_tag() {
  mkdir -p "${ROOT}/out"
  printf '%s\n' "${KSU_TAG}" > "$(ksu_stamp_file)"
  if [ -n "${GITHUB_ENV:-}" ]; then
    {
      echo "KSU_TAG=${KSU_TAG}"
    } >> "${GITHUB_ENV}"
  fi
}

ksu_zip_prefix() {
  local t="${KSU_TAG:-}"
  if [ -z "${t}" ] && [ -n "${ROOT:-}" ] && [ -f "$(ksu_stamp_file)" ]; then
    t="$(tr -d '[:space:]' < "$(ksu_stamp_file)")"
  fi
  if [ -z "${t}" ] && [ -n "${ROOT:-}" ] && [ -d "${ROOT}/gki/common/KernelSU/.git" ]; then
    t="$(git -C "${ROOT}/gki/common/KernelSU" describe --tags --exact-match HEAD 2>/dev/null || true)"
  fi
  t="${t:-tag}"
  t="${t//\//-}"
  printf 'KernelSU-%s' "${t}"
}

# Zip token after 4k-. 官方 KernelSU + 10_ 有 SUSFS 菜单且已启用。
ksu_zip_susfs_mark() {
  printf 'SUSFS-'
}

# anykernel kernel.string extra features.
ksu_kernel_ver_extra() {
  printf 'SUSFS+RFKILL'
}
