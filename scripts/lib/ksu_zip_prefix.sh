#!/usr/bin/env bash
# Shared SukiSU tag / artifact prefix. Sourced by 02, 06, 07.

ksu_latest_tag() {
  local repo="${1:-${KSU_REPO:-https://github.com/SukiSU-Ultra/SukiSU-Ultra.git}}"
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
    echo "could not resolve latest SukiSU tag from ${repo}" >&2
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
      echo "KSU_FLAVOR=${KSU_FLAVOR}"
    } >> "${GITHUB_ENV}"
  fi
}

ksu_zip_prefix() {
  case "${KSU_FLAVOR:-builtin}" in
    tag|main|main-susfs)
      local t="${KSU_TAG:-}"
      if [ -z "${t}" ] && [ -n "${ROOT:-}" ] && [ -f "$(ksu_stamp_file)" ]; then
        t="$(tr -d '[:space:]' < "$(ksu_stamp_file)")"
      fi
      if [ -z "${t}" ] && [ -n "${ROOT:-}" ] && [ -d "${ROOT}/gki/common/KernelSU/.git" ]; then
        t="$(git -C "${ROOT}/gki/common/KernelSU" describe --tags --exact-match HEAD 2>/dev/null || true)"
      fi
      t="${t:-tag}"
      t="${t//\//-}"
      printf 'SukiSU-%s' "${t}"
      ;;
    *)
      printf 'SukiSU'
      ;;
  esac
}
