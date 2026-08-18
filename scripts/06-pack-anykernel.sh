#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VARIANT="${AOSP_VARIANT:-aosp-release}"
CHANNEL="${AK3_CHANNEL:-REL}"
DIST="${AOSP_DIST:-${ROOT}/out/${VARIANT}}"
AK_DIR="${ROOT}/third_party/AnyKernel3"
STAGE="${ROOT}/out/ak3-${VARIANT}"

KVER="$(awk '/^VERSION =/{v=$3} /^PATCHLEVEL =/{p=$3} /^SUBLEVEL =/{s=$3} END{print v"."p"."s}' \
  "${ROOT}/gki/common/Makefile")"
VER="${KVER}+SUSFS+RFKILL+${CHANNEL}"
ZIP_NAME="${AK3_ZIP_NAME:-SukiSU-annibale-aosp-${KVER}-4k-SUSFS-${CHANNEL}-AnyKernel3.zip}"
KERNEL_STRING="SukiSU Ultra GKI ${VER} 4k for REDMI K90 (annibale)"

case "${AK_DIR}" in
  "${ROOT}"/third_party/*) ;;
  *) echo "refuse rm outside seed tree: ${AK_DIR}" >&2; exit 1 ;;
esac
case "${STAGE}" in
  "${ROOT}"/out/*) ;;
  *) echo "refuse rm outside seed tree: ${STAGE}" >&2; exit 1 ;;
esac

# 官方 v2.2.0：WildPlusKernel/AnyKernel3 @ gki-2.0，默认 zip 只放未压缩 Image。
rm -rf -- "${AK_DIR}"
git clone --depth=1 --branch gki-2.0 \
  https://github.com/WildPlusKernel/AnyKernel3.git "${AK_DIR}"

rm -rf -- "${STAGE}"
mkdir -p -- "${STAGE}"
rsync -a --exclude='.git' --exclude='*.zip' "${AK_DIR}/" "${STAGE}/"
rm -f -- "${STAGE}"/Image* "${STAGE}"/*.zip "${STAGE}/banner"
cp -f -- "${DIST}/Image" "${STAGE}/Image"

# 官方 anykernel.sh 骨架 + LKM su 下用 sysfs 解析 boot 绝对路径。
# 必须在 source ak3-core.sh 之前设好 block=：setup_ak 在 source 末尾就会跑。
# 只认 boot / boot_a / boot_b，DEVNAME 只允许简单块名，避免写到错误分区。
cat > "${STAGE}/anykernel.sh" <<'EOF'
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=KERNEL_STRING_PLACEHOLDER
do.devicecheck=0
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
do.check_boot_version=0
device.name1=
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
keycheck.timeout=10
'; } # end properties

trim() {
  printf '%s' "$1" | tr -d '\r\n\t '
}

safe_name() {
  case "$1" in
    ''|*[!A-Za-z0-9._-]*|*/*|*..*) return 1 ;;
  esac
  return 0
}

read_uevent_field() {
  local val
  val=$(grep "^$2=" "$1" 2>/dev/null | head -n1 | cut -d= -f2-)
  trim "$val"
}

current_slot() {
  local slot
  slot=$(trim "$(getprop ro.boot.slot_suffix 2>/dev/null)")
  [ -n "$slot" ] || slot=$(trim "$(grep -o 'androidboot.slot_suffix=[^ ]*' /proc/cmdline 2>/dev/null | cut -d= -f2)")
  if [ -z "$slot" ]; then
    slot=$(trim "$(getprop ro.boot.slot 2>/dev/null)")
    [ -n "$slot" ] || slot=$(trim "$(grep -o 'androidboot.slot=[^ ]*' /proc/cmdline 2>/dev/null | cut -d= -f2)")
    [ -n "$slot" ] && [ "$slot" != "normal" ] && slot=_$slot
  fi
  [ "$slot" = "normal" ] && slot=
  case "$slot" in
    ''|_a|_b) printf '%s' "$slot" ;;
    a|b) printf '_%s' "$slot" ;;
    *) printf '' ;;
  esac
}

wanted_part() {
  local slot
  slot=$(current_slot)
  if [ -n "$slot" ]; then
    printf 'boot%s' "$slot"
  else
    printf 'boot'
  fi
}

accept_partname() {
  local name="$1" want
  want=$(wanted_part)
  [ "$name" = "$want" ]
}

is_boot_block_path() {
  case "$1" in
    /dev/block/by-name/boot|/dev/block/by-name/boot_a|/dev/block/by-name/boot_b) ;;
    /dev/block/bootdevice/by-name/boot|/dev/block/bootdevice/by-name/boot_a|/dev/block/bootdevice/by-name/boot_b) ;;
    /dev/block/[A-Za-z][A-Za-z0-9._-]*) ;;
    *) return 1 ;;
  esac
  [ -b "$1" ]
}

ensure_block_node() {
  local dev="$1" uevent="$2" major minor dest
  safe_name "$dev" || return 1
  dest="/dev/block/$dev"
  if [ -b "$dest" ]; then
    printf '%s\n' "$dest"
    return 0
  fi
  if [ -e "$dest" ]; then
    return 1
  fi
  major=$(read_uevent_field "$uevent" MAJOR)
  minor=$(read_uevent_field "$uevent" MINOR)
  case "$major" in ''|*[!0-9]*) return 1 ;; esac
  case "$minor" in ''|*[!0-9]*) return 1 ;; esac
  mkdir -p /dev/block
  mknod "$dest" b "$major" "$minor" 2>/dev/null || return 1
  [ -b "$dest" ] || return 1
  ui_print "  mknod $dest $major:$minor"
  printf '%s\n' "$dest"
}

debug_boot_candidates() {
  local uevent name dev major minor
  ui_print " " "slot_suffix=$(current_slot) want=$(wanted_part)"
  ui_print "by-name: $(ls /dev/block/by-name/boot /dev/block/by-name/boot_a /dev/block/by-name/boot_b 2>/dev/null)"
  ui_print "bootdevice: $(ls /dev/block/bootdevice/by-name/boot /dev/block/bootdevice/by-name/boot_a /dev/block/bootdevice/by-name/boot_b 2>/dev/null)"
  ui_print "sysfs PARTNAME=boot* :"
  for uevent in /sys/dev/block/*/uevent; do
    [ -f "$uevent" ] || continue
    name=$(read_uevent_field "$uevent" PARTNAME)
    case $name in
      boot|boot_a|boot_b|BOOT|BOOT_A|BOOT_B)
        dev=$(read_uevent_field "$uevent" DEVNAME)
        major=$(read_uevent_field "$uevent" MAJOR)
        minor=$(read_uevent_field "$uevent" MINOR)
        ui_print "  $name dev=$dev $major:$minor"
        ;;
    esac
  done
}

resolve_boot_block() {
  local slot part name dev path uevent
  slot=$(current_slot)
  part=$(wanted_part)

  for path in \
    "/dev/block/by-name/$part" \
    "/dev/block/bootdevice/by-name/$part"
  do
    if is_boot_block_path "$path"; then
      printf '%s\n' "$path"
      return 0
    fi
  done

  for uevent in /sys/dev/block/*/uevent; do
    [ -f "$uevent" ] || continue
    name=$(read_uevent_field "$uevent" PARTNAME)
    accept_partname "$name" || continue
    dev=$(read_uevent_field "$uevent" DEVNAME)
    path=$(ensure_block_node "$dev" "$uevent") || continue
    is_boot_block_path "$path" || continue
    printf '%s\n' "$path"
    return 0
  done
  return 1
}

### AnyKernel install
debug_boot_candidates
resolved=$(resolve_boot_block | head -n 1)
resolved=$(trim "$resolved")
if is_boot_block_path "$resolved"; then
  ui_print "boot block: $resolved"
  block="$resolved"
else
  ui_print "boot block: unresolved, abort rather than guess"
  abort "Unable to determine boot partition safely. Aborting..."
fi
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=1

. tools/ak3-core.sh

kernel_version=$(cat /proc/version | awk -F '-' '{print $1}' | awk '{print $3}')
case $kernel_version in
  5.10*|5.15*|6.1*|6.6*|6.12*) ksu_supported=true ;;
  *) ksu_supported=false ;;
esac
ui_print " " "  -> GKI supported: $ksu_supported"
$ksu_supported || abort "  -> Non-GKI device, abort."

split_boot
if [ -f "$SPLITIMG/ramdisk.cpio" ]; then
  unpack_ramdisk
  write_boot
else
  flash_boot
fi
EOF

python3 -c '
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text(encoding="utf-8").replace("KERNEL_STRING_PLACEHOLDER", sys.argv[2], 1), encoding="utf-8")
' "${STAGE}/anykernel.sh" "${KERNEL_STRING}"

(
  cd "${STAGE}"
  rm -f -- "${ROOT}/out/${ZIP_NAME}"
  zip -r9 "${ROOT}/out/${ZIP_NAME}" . -x '*.git*'
)
echo "packed ${ROOT}/out/${ZIP_NAME}"
