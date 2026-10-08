#!/usr/bin/env bash
# Shared AnyKernel3 / artifact prefix. Sourced by 06 and 07.

ksu_zip_prefix() {
  case "${KSU_FLAVOR:-builtin}" in
    main|main-susfs)
      local t="${KSU_TAG:-v4.2.0}"
      t="${t//\//-}"
      printf 'SukiSU-%s' "${t}"
      ;;
    *)
      printf 'SukiSU'
      ;;
  esac
}
