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
# 管理器下的 kpm/kptools 是 Android aarch64（interpreter /system/bin/linker64），CI 不能 qemu。
# kpimg 仍用管理器同一份；kptools 用 SukiSU 的 Linux 主机版。
KPTOOLS_URL="${KPTOOLS_URL:-https://github.com/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/download/0.13.0/kptools-linux}"
KPIMG_URL="${KPIMG_URL:-https://raw.githubusercontent.com/ShirkNeko/SukiSU_patch/refs/heads/main/kpm/kpimg}"
PATCH_LINUX_URL="${PATCH_LINUX_URL:-https://raw.githubusercontent.com/ShirkNeko/SukiSU_patch/refs/heads/main/kpm/patch_linux}"

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

# Android 动态链接的 kptools 在 Linux 上跑不了，换成 SukiSU 的 linux 主机版。
if echo "${kptools_info}" | grep -qi 'linker64\|Android'; then
  echo "got Android kptools; downloading kptools-linux instead"
  curl -fL --retry 3 -o "${TOOLS}/kptools" \
    "https://github.com/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/download/0.13.0/kptools-linux"
  chmod a+rx -- "${TOOLS}/kptools"
  kptools_info="$(file -b "${TOOLS}/kptools")"
  echo "kptools: $(wc -c < "${TOOLS}/kptools") bytes (${kptools_info})"
fi

run_kptools() {
  if echo "${kptools_info}" | grep -qi 'x86-64\|x86_64\|Intel 80386'; then
    "${TOOLS}/kptools" "$@"
    return
  fi
  echo "unsupported kptools for CI host: ${kptools_info}" >&2
  exit 1
}

rm -rf -- "${WORK}"
mkdir -p -- "${WORK}"
cp -f -- "${DIST}/Image" "${WORK}/Image"
cp -f -- "${TOOLS}/kptools" "${TOOLS}/kpimg" "${WORK}/"
src_size="$(wc -c < "${WORK}/Image")"
echo "patching Image (${src_size} bytes) with kptools -p -s ${KPM_KEY}"
set +e
(
  cd "${WORK}"
  chmod a+rx ./kptools
  run_kptools -p -s "${KPM_KEY}" -i Image -k kpimg -o oImage
)
kptools_rc=$?
set -e
if [[ ! -f "${WORK}/oImage" ]]; then
  echo "kptools failed (rc=${kptools_rc}); fallback to SukiSU_patch patch_linux"
  curl -fL --retry 3 -o "${WORK}/patch_linux" "${PATCH_LINUX_URL}"
  chmod a+rx -- "${WORK}/patch_linux"
  (
    cd "${WORK}"
    ./patch_linux
  )
fi
if [[ ! -f "${WORK}/oImage" ]]; then
  echo "no oImage from kptools or patch_linux" >&2
  exit 1
fi
out_size="$(wc -c < "${WORK}/oImage")"
echo "patched Image: ${out_size} bytes"
if [[ "${out_size}" -le "${src_size}" ]]; then
  echo "patched Image is not larger than source; refuse" >&2
  exit 1
fi

cp -f -- "${WORK}/oImage" "${DIST}/Image-kpm"
# AOSP/GKI 的 Image.lz4 是 legacy（02 21 4C 18），不是默认 frame（04 22 4D 18）。
# 用错格式时 bootloader 解不开内核，fastboot boot 会黑屏、没有开机动画。
lz4 -f -l -12 --favor-decSpeed "${DIST}/Image-kpm" "${DIST}/Image-kpm.lz4"
echo "wrote ${DIST}/Image-kpm"
echo "wrote ${DIST}/Image-kpm.lz4"
python3 - "${DIST}/Image.lz4" "${DIST}/Image-kpm.lz4" <<'PY'
import sys
from pathlib import Path

LEGACY = b"\x02\x21\x4c\x18"
FRAME = b"\x04\x22\x4d\x18"

def magic(p):
    b = Path(p).read_bytes()[:4]
    return b.hex(), {LEGACY: "lz4-legacy", FRAME: "lz4-frame"}.get(b, "unknown")

ok = True
for p in sys.argv[1:]:
    path = Path(p)
    if not path.exists():
        continue
    hx, name = magic(path)
    print(f"{p}: {name} ({hx})")
    if path.name == "Image-kpm.lz4" and name != "lz4-legacy":
        print(f"Image-kpm.lz4 must be lz4-legacy (02214c18), got {name}", file=sys.stderr)
        ok = False
if not ok:
    sys.exit(1)
PY

find_avbtool() {
  local p
  if command -v avbtool >/dev/null 2>&1; then
    command -v avbtool
    return 0
  fi
  for p in \
    "${ROOT}/gki/prebuilts/kernel-build-tools/linux-x86/bin/avbtool" \
    "${ROOT}/gki/prebuilts/build-tools/linux-x86/bin/avbtool" \
    "${ROOT}/gki/external/avb/avbtool.py"
  do
    if [[ -f "${p}" ]]; then
      echo "${p}"
      return 0
    fi
  done
  p="$(find "${ROOT}/gki" -type f \( -name avbtool -o -name avbtool.py \) 2>/dev/null | head -n1 || true)"
  if [[ -n "${p}" ]]; then
    echo "${p}"
    return 0
  fi
  return 1
}

run_avbtool() {
  local tool="$1"
  shift
  if [[ "${tool}" == *.py ]] || grep -q '^#!.*python' "${tool}" 2>/dev/null; then
    python3 "${tool}" "$@"
  else
    "${tool}" "$@"
  fi
}

# AOSP boot-lz4.img 是 51MiB + AVB hash footer。只写 header+kernel（约 17MB）
# 时 Xiaomi bootloader 不认，fastboot boot 黑屏。必须按原分区大小重打 footer。
rebuild_boot_kpm() {
  local src_boot="$1" dst_boot="$2" kernel="$3"
  local avbtool part_size patch_prop meta
  meta="${WORK}/boot-kpm.meta"
  python3 - "${src_boot}" "${kernel}" "${dst_boot}" "${meta}" <<'PY'
import re, struct, sys
from pathlib import Path

boot_path, kernel_path, out_path, meta_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
boot = Path(boot_path).read_bytes()
kernel = Path(kernel_path).read_bytes()
if boot[:8] != b"ANDROID!":
    raise SystemExit(f"not an Android boot image: {boot_path}")
if len(boot) < 4096:
    raise SystemExit("boot header page missing")
old_ksize, _ramdisk, _os, hdr_size = struct.unpack_from("<IIII", boot, 8)
hdr_ver = struct.unpack_from("<I", boot, 40)[0]
if hdr_size < 44 or hdr_size > 4096:
    raise SystemExit(f"bad header_size {hdr_size}")
page = 4096
hdr = bytearray(boot[:page])
struct.pack_into("<I", hdr, 8, len(kernel))
if hdr_ver >= 4 and hdr_size >= 1584:
    struct.pack_into("<I", hdr, 1580, 0)
kpad = (len(kernel) + page - 1) // page * page
Path(out_path).write_bytes(bytes(hdr) + kernel.ljust(kpad, b"\0"))
prop = ""
m = re.search(br"com\.android\.build\.boot\.security_patch\x00*(20\d{2}-\d{2}-\d{2})", boot)
if m:
    prop = m.group(1).decode("ascii")
Path(meta_path).write_text(f"{len(boot)}\n{prop}\n", encoding="ascii")
print(f"raw {out_path} hdr_v{hdr_ver} kernel {old_ksize}->{len(kernel)} src={len(boot)} patch={prop or 'none'}")
PY
  part_size="$(sed -n '1p' "${meta}")"
  patch_prop="$(sed -n '2p' "${meta}")"

  if ! avbtool="$(find_avbtool)"; then
    echo "avbtool not in PATH/gki; downloading avbtool.py"
    curl -fL --retry 3 -o "${TOOLS}/avbtool.py" \
      "https://raw.githubusercontent.com/LineageOS/android_external_avb/lineage-22.2/avbtool.py"
    avbtool="${TOOLS}/avbtool.py"
  fi
  echo "avbtool: ${avbtool} partition_size=${part_size} security_patch=${patch_prop:-none}"
  if [[ -n "${patch_prop}" ]]; then
    run_avbtool "${avbtool}" add_hash_footer \
      --image "${dst_boot}" \
      --partition_size "${part_size}" \
      --partition_name boot \
      --prop "com.android.build.boot.security_patch:${patch_prop}"
  else
    run_avbtool "${avbtool}" add_hash_footer \
      --image "${dst_boot}" \
      --partition_size "${part_size}" \
      --partition_name boot
  fi
  python3 - "${src_boot}" "${dst_boot}" <<'PY'
import sys
from pathlib import Path
src, dst = Path(sys.argv[1]).read_bytes(), Path(sys.argv[2]).read_bytes()
if dst[:8] != b"ANDROID!":
    raise SystemExit("rebuilt boot lost ANDROID! magic")
if dst[-64:-60] != b"AVBf":
    raise SystemExit("rebuilt boot missing AVB footer")
if len(dst) != len(src):
    raise SystemExit(f"rebuilt size {len(dst)} != source {len(src)}")
print(f"rebuilt {sys.argv[2]} size {len(dst)} AVBf ok")
PY
}

# annibale 上已验证：fastboot boot 只能用未压缩 boot.img（内核是 MZ/Image）。
# boot-lz4.img / boot-kpm-lz4.img 在这台机上进不去，包括未打 kpimg 的 REL-3。
if [[ -f "${DIST}/boot.img" ]]; then
  rebuild_boot_kpm "${DIST}/boot.img" "${DIST}/boot-kpm.img" "${DIST}/Image-kpm"
fi
if [[ -f "${DIST}/boot-lz4.img" ]]; then
  rebuild_boot_kpm "${DIST}/boot-lz4.img" "${DIST}/boot-kpm-lz4.img" "${DIST}/Image-kpm.lz4" \
    || echo "warn: boot-kpm-lz4.img rebuild failed (not used on annibale)"
fi
if [[ ! -f "${DIST}/boot-kpm.img" && ! -f "${DIST}/boot-kpm-lz4.img" ]]; then
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
