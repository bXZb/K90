#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VARIANT="${AOSP_VARIANT:-aosp-release}"
CHANNEL="${AK3_CHANNEL:-REL}"
DIST="${AOSP_DIST:-${ROOT}/out/${VARIANT}}"
STAGE="${ROOT}/out/ak3-${VARIANT}"
WORK="${ROOT}/out/kpm-work"
TOOLS="${ROOT}/out/kpm-tools"
KPM_KEY="${KPM_KEY:-123}"
KPTOOLS_URL="${KPTOOLS_URL:-https://raw.githubusercontent.com/ShirkNeko/SukiSU_patch/refs/heads/main/kpm/kptools}"
KPIMG_URL="${KPIMG_URL:-https://raw.githubusercontent.com/ShirkNeko/SukiSU_patch/refs/heads/main/kpm/kpimg}"

case "${VARIANT}" in
  *[!A-Za-z0-9._-]*) echo "unsafe AOSP_VARIANT=${VARIANT}" >&2; exit 1 ;;
esac
case "${CHANNEL}" in
  *[!A-Za-z0-9._-]*) echo "unsafe AK3_CHANNEL=${CHANNEL}" >&2; exit 1 ;;
esac
case "${KPM_KEY}" in
  *[!A-Za-z0-9._-]*) echo "unsafe KPM_KEY" >&2; exit 1 ;;
esac

KVER="$(awk '
  /^VERSION[[:space:]]*=/ { v=$3 }
  /^PATCHLEVEL[[:space:]]*=/ { p=$3 }
  /^SUBLEVEL[[:space:]]*=/ { s=$3 }
  END {
    if (v == "" || p == "" || s == "") exit 1
    if (v !~ /^[0-9]+$/ || p !~ /^[0-9]+$/ || s !~ /^[0-9]+$/) exit 1
    print v "." p "." s
  }
' "${ROOT}/gki/common/Makefile")"
KPM_ZIP_NAME="${KPM_AK3_ZIP_NAME:-SukiSU-annibale-aosp-${KVER}-4k-SUSFS-${CHANNEL}-KPM-AnyKernel3.zip}"

case "${KPM_ZIP_NAME}" in
  *[!A-Za-z0-9._+-]*|/*|*..*) echo "unsafe KPM zip name" >&2; exit 1 ;;
esac

if [[ ! -f "${DIST}/Image" ]]; then
  echo "missing ${DIST}/Image" >&2
  exit 1
fi

if ! command -v lz4 >/dev/null 2>&1 || ! command -v file >/dev/null 2>&1; then
  echo "need lz4 and file" >&2
  exit 1
fi

mkdir -p -- "${TOOLS}" "${WORK}"
curl -fL --retry 3 -o "${TOOLS}/kptools" "${KPTOOLS_URL}"
curl -fL --retry 3 -o "${TOOLS}/kpimg" "${KPIMG_URL}"
chmod a+rx -- "${TOOLS}/kptools"

kptools_info="$(file -b "${TOOLS}/kptools")"
kpimg_size="$(wc -c < "${TOOLS}/kpimg")"
kptools_size="$(wc -c < "${TOOLS}/kptools")"
echo "kptools: ${kptools_size} bytes (${kptools_info})"
echo "kpimg: ${kpimg_size} bytes"
if [[ "${kptools_size}" -lt 1024 || "${kpimg_size}" -lt 1024 ]]; then
  echo "kpm tools too small" >&2
  exit 1
fi

run_kptools() {
  if echo "${kptools_info}" | grep -qi 'x86-64\|x86_64\|Intel 80386'; then
    "${TOOLS}/kptools" "$@"
    return
  fi
  if echo "${kptools_info}" | grep -qi 'aarch64\|ARM aarch64'; then
    if ! command -v qemu-aarch64-static >/dev/null 2>&1; then
      if command -v sudo >/dev/null 2>&1; then
        sudo apt-get install -y --no-install-recommends qemu-user-static
      else
        echo "need qemu-aarch64-static to run android kptools" >&2
        exit 1
      fi
    fi
    qemu-aarch64-static "${TOOLS}/kptools" "$@"
    return
  fi
  echo "unsupported kptools arch: ${kptools_info}" >&2
  exit 1
}

rm -rf -- "${WORK}"
mkdir -p -- "${WORK}"
cp -f -- "${DIST}/Image" "${WORK}/Image"
cp -f -- "${TOOLS}/kptools" "${TOOLS}/kpimg" "${WORK}/"
src_size="$(wc -c < "${WORK}/Image")"
echo "patching Image (${src_size} bytes) with kptools -p -s ${KPM_KEY}"
(
  cd "${WORK}"
  chmod a+rx ./kptools
  run_kptools -p -s "${KPM_KEY}" -i Image -k kpimg -o oImage
)
if [[ ! -f "${WORK}/oImage" ]]; then
  echo "kptools produced no oImage" >&2
  exit 1
fi
out_size="$(wc -c < "${WORK}/oImage")"
echo "patched Image: ${out_size} bytes"
if [[ "${out_size}" -le "${src_size}" ]]; then
  echo "patched Image is not larger than source; refuse" >&2
  exit 1
fi

cp -f -- "${WORK}/oImage" "${DIST}/Image-kpm"
lz4 -f -12 "${DIST}/Image-kpm" "${DIST}/Image-kpm.lz4"
echo "wrote ${DIST}/Image-kpm"
echo "wrote ${DIST}/Image-kpm.lz4"

rebuild_boot_kpm() {
  local src_boot="$1" dst_boot="$2" kernel="$3"
  python3 - "${src_boot}" "${kernel}" "${dst_boot}" <<'PY'
import struct, sys
from pathlib import Path

boot_path, kernel_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
boot = Path(boot_path).read_bytes()
kernel = Path(kernel_path).read_bytes()
if boot[:8] != b"ANDROID!":
    raise SystemExit(f"not an Android boot image: {boot_path}")
if len(boot) < 44:
    raise SystemExit("boot header too small")
old_ksize, ramdisk_size, os_version, hdr_size = struct.unpack_from("<IIII", boot, 8)
hdr_ver = struct.unpack_from("<I", boot, 40)[0]
if hdr_size < 44 or hdr_size > len(boot):
    raise SystemExit(f"bad header_size {hdr_size}")
page = 4096
hdr_pages = (hdr_size + page - 1) // page
new_hdr = bytearray(boot[:hdr_size])
struct.pack_into("<I", new_hdr, 8, len(kernel))
if hdr_ver >= 4 and hdr_size >= 1584:
    struct.pack_into("<I", new_hdr, 1580, 0)
kpad = (len(kernel) + page - 1) // page * page
out = bytes(new_hdr).ljust(hdr_pages * page, b"\0") + kernel.ljust(kpad, b"\0")
Path(out_path).write_bytes(out)
print(f"rebuilt {out_path} from {boot_path} (hdr_v{hdr_ver}, kernel {old_ksize}->{len(kernel)})")
PY
}

if [[ -f "${DIST}/boot-lz4.img" ]]; then
  rebuild_boot_kpm "${DIST}/boot-lz4.img" "${DIST}/boot-kpm-lz4.img" "${DIST}/Image-kpm.lz4" \
    || echo "warn: could not rebuild boot-kpm-lz4.img"
elif [[ -f "${DIST}/boot.img" ]]; then
  rebuild_boot_kpm "${DIST}/boot.img" "${DIST}/boot-kpm.img" "${DIST}/Image-kpm" \
    || echo "warn: could not rebuild boot-kpm.img"
else
  echo "no boot.img/boot-lz4.img; skip boot-kpm"
fi

if [[ -d "${STAGE}" && -f "${STAGE}/anykernel.sh" ]]; then
  cp -f -- "${DIST}/Image-kpm" "${STAGE}/Image"
  (
    cd "${STAGE}"
    rm -f -- "${ROOT}/out/${KPM_ZIP_NAME}"
    zip -r9 "${ROOT}/out/${KPM_ZIP_NAME}" . -x '*.git*'
  )
  echo "packed ${ROOT}/out/${KPM_ZIP_NAME}"
else
  echo "AK3 stage missing; skip KPM zip (run 05 first)"
fi
