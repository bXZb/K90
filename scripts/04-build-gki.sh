#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="${ROOT}/gki"
DIST="${AOSP_DIST:-${ROOT}/out/aosp-release}"
LTO="${LTO:-thin}"

auto_jobs() {
  local cpus mem_gb jobs
  cpus="$(nproc)"
  mem_gb="$(awk '/MemTotal/{print int($2/1024/1024)}' /proc/meminfo)"
  # thin LTO 大约每 job 4GB，给系统和 bazel 留 4GB。
  jobs=$(( (mem_gb - 4) / 4 ))
  [[ "${jobs}" -gt "${cpus}" ]] && jobs="${cpus}"
  [[ "${jobs}" -lt 1 ]] && jobs=1
  echo "${jobs}"
}

if [[ -z "${BUILD_JOBS:-}" || "${BUILD_JOBS}" == "auto" ]]; then
  JOBS="$(auto_jobs)"
else
  JOBS="${BUILD_JOBS}"
fi

mkdir -p "${DIST}"
cd "${WORKDIR}"
tools/bazel run \
  --jobs="${JOBS}" \
  --lto="${LTO}" \
  //common:kernel_aarch64_dist -- --destdir="${DIST}"
