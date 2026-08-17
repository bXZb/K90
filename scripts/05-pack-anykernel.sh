#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VARIANT="${AOSP_VARIANT:-aosp-release}"
CHANNEL="${AK3_CHANNEL:-REL}"
DIST="${AOSP_DIST:-${ROOT}/out/${VARIANT}}"
AK_DIR="${ROOT}/third_party/AnyKernel3"
STAGE="${ROOT}/out/ak3-${VARIANT}"
KVER="$(awk '
  /^VERSION[[:space:]]*=/ { v=$3 }
  /^PATCHLEVEL[[:space:]]*=/ { p=$3 }
  /^SUBLEVEL[[:space:]]*=/ { s=$3 }
  END {
    if (v == "" || p == "" || s == "") exit 1
    print v "." p "." s
  }
' "${ROOT}/gki/common/Makefile")"
VER="${KVER}+SUSFS+RFKILL+${CHANNEL}"
ZIP_NAME="${AK3_ZIP_NAME:-SukiSU-annibale-aosp-${KVER}-4k-SUSFS-${CHANNEL}-AnyKernel3.zip}"

git clone --depth=1 https://github.com/osm0sis/AnyKernel3.git "${AK_DIR}"

rm -rf "${STAGE}"
mkdir -p "${STAGE}"
rsync -a --exclude='.git' --exclude='*.zip' "${AK_DIR}/" "${STAGE}/"
rm -f "${STAGE}"/Image* "${STAGE}"/*.zip
# 小米 GKI 的 boot 里内核是 lz4。只放 Image.lz4，避免 AK3 选中未压缩 Image 把 boot 撑爆。
cp -f "${DIST}/Image.lz4" "${STAGE}/Image.lz4"

cat > "${STAGE}/anykernel.sh" <<EOF
# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers

## AnyKernel setup
properties() { '
kernel.string=SukiSU Ultra GKI ${VER} 4k for REDMI K90 (annibale)
do.devicecheck=0
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
'; }

block=boot;
is_slot_device=auto;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

. tools/ak3-core.sh;

ui_print "SukiSU Ultra ${VARIANT} GKI ${VER} 4k";
ui_print "device: annibale / 2510DRK44C";

# GKI：boot 只有内核，ramdisk 在 init_boot。不要 dump_boot/write_boot。
split_boot;
flash_boot;
EOF

(
  cd "${STAGE}"
  rm -f "${ROOT}/out/${ZIP_NAME}"
  zip -r9 "${ROOT}/out/${ZIP_NAME}" . -x '*.git*'
)
echo "packed ${ROOT}/out/${ZIP_NAME}"
