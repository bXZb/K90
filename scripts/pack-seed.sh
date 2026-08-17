#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/out/k90-gki-seed-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"

mkdir -p "${ROOT}/out"
mapfile -t FILES < <(grep -vE '^\s*(#|$)' "${ROOT}/SEED-FILES.txt")
tar -C "${ROOT}" -czf "${OUT}" "${FILES[@]}"
