#!/usr/bin/env bash
set -euo pipefail

# kptools 必须用 Linux 主机版。管理器里的是 aarch64 + linker64，CI 跑不了。
# annibale 已验证：fastboot boot 用未压缩 boot.img / boot-kpm.img，不用 *-lz4.img。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VARIANT="${AOSP_VARIANT:-aosp-release}"
CHANNEL="${AK3_CHANNEL:-REL}"
DIST="${AOSP_DIST:-${ROOT}/out/${VARIANT}}"
STAGE="${ROOT}/out/ak3-${VARIANT}"
WORK="${ROOT}/out/kpm-work"
TOOLS="${ROOT}/out/kpm-tools"
KPM_KEY="${KPM_KEY:-123}"
KPTOOLS_URL="${KPTOOLS_URL:-https://github.com/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/download/0.13.0/kptools-linux}"
# 仓库已从 ShirkNeko/SukiSU_patch 转移到 SukiSU-Ultra/SukiSU_patch。
# kpimg pin 到固定 commit（547ae94b，2026-03-15 "更新kpm版本"）；升级 = 显式换 SHA。
KPIMG_URL="${KPIMG_URL:-https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU_patch/547ae94bcaec53d030398f857950c64662043a5d/kpm/kpimg}"
AVBTOOL="${ROOT}/gki/prebuilts/kernel-build-tools/linux-x86/bin/avbtool"

KVER="$(awk '/^VERSION =/{v=$3} /^PATCHLEVEL =/{p=$3} /^SUBLEVEL =/{s=$3} END{print v"."p"."s}' \
  "${ROOT}/gki/common/Makefile")"
case "${KSU_FLAVOR:-builtin}" in
  main-susfs) KSU_TAG="SukiSU-Main" ;;
  *)          KSU_TAG="SukiSU" ;;
esac
KPM_ZIP_NAME="${KPM_AK3_ZIP_NAME:-${KSU_TAG}-annibale-aosp-${KVER}-4k-SUSFS-${CHANNEL}-KPM-AnyKernel3.zip}"

rm -rf "${WORK}"
mkdir -p "${TOOLS}" "${WORK}"
curl -fL --retry 3 -o "${TOOLS}/kptools" "${KPTOOLS_URL}"
curl -fL --retry 3 -o "${TOOLS}/kpimg" "${KPIMG_URL}"
chmod a+rx "${TOOLS}/kptools"

cp -f "${DIST}/Image" "${TOOLS}/kptools" "${TOOLS}/kpimg" "${WORK}/"
echo "patching Image ($(wc -c < "${WORK}/Image") bytes) with kptools -s ${KPM_KEY}"
(
  cd "${WORK}"
  ./kptools -p -s "${KPM_KEY}" -i Image -k kpimg -o oImage
)
cp -f "${WORK}/oImage" "${DIST}/Image-kpm"
echo "wrote ${DIST}/Image-kpm ($(wc -c < "${DIST}/Image-kpm") bytes)"

# 保留源 boot 头和分区大小，只换内核，再打和 kleaf 一样的 AVB hash footer。
read -r PART_SIZE PATCH < <(python3 - "${DIST}/boot.img" "${DIST}/Image-kpm" "${DIST}/boot-kpm.img" <<'PY'
import re, struct, sys
from pathlib import Path

boot = Path(sys.argv[1]).read_bytes()
kernel = Path(sys.argv[2]).read_bytes()
hdr = bytearray(boot[:4096])
struct.pack_into("<I", hdr, 8, len(kernel))
if struct.unpack_from("<I", hdr, 40)[0] >= 4:
    struct.pack_into("<I", hdr, 1580, 0)
kpad = (len(kernel) + 4095) // 4096 * 4096
Path(sys.argv[3]).write_bytes(bytes(hdr) + kernel.ljust(kpad, b"\0"))
prop = ""
m = re.search(br"com\.android\.build\.boot\.security_patch\x00*(20\d{2}-\d{2}-\d{2})", boot)
if m:
    prop = m.group(1).decode("ascii")
print(len(boot), prop)
PY
)
echo "avbtool ${AVBTOOL} partition_size=${PART_SIZE} security_patch=${PATCH:-none}"
if [[ -n "${PATCH}" ]]; then
  "${AVBTOOL}" add_hash_footer \
    --image "${DIST}/boot-kpm.img" \
    --partition_size "${PART_SIZE}" \
    --partition_name boot \
    --prop "com.android.build.boot.security_patch:${PATCH}"
else
  "${AVBTOOL}" add_hash_footer \
    --image "${DIST}/boot-kpm.img" \
    --partition_size "${PART_SIZE}" \
    --partition_name boot
fi
echo "wrote ${DIST}/boot-kpm.img ($(wc -c < "${DIST}/boot-kpm.img") bytes)"

cp -f "${DIST}/Image-kpm" "${STAGE}/Image"
(
  cd "${STAGE}"
  rm -f "${ROOT}/out/${KPM_ZIP_NAME}"
  zip -r9 "${ROOT}/out/${KPM_ZIP_NAME}" . -x '*.git*'
)
echo "packed ${ROOT}/out/${KPM_ZIP_NAME}"
