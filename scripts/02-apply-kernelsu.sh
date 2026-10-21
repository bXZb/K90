#!/usr/bin/env bash
set -euo pipefail

# 官方 KernelSU（tiann/KernelSU）in-tree 集成 + SUSFS。
# susfs4ksu 每次 "Sync with the official KernelSU main repo" 提交的消息里都写明
# 对应的 tiann commit。默认策略（联动解析）：susfs 跟 HEAD，KSU checkout 到其
# 最新 sync 点 —— 10_ 与驱动按构造对齐（susfs 作者就是拿那个点验证补丁的）。
# 手动覆盖：KSU_TAG / KSU_COMMIT 指定驱动侧，SUSFS_COMMIT pin susfs 侧；
# 任一驱动侧输入生效即跳过联动解析。
# 流程：clone susfs（并解析）→ clone KernelSU 到解析点 → 10_ 补丁打进驱动
#      → symlink/Makefile/Kconfig 挂接 → defconfig fragment
#      → susfs fs/include + 50_ 补丁 → 打开 SUSFS 菜单。
# 官方 v3.x kernel/ 目录同时带 Kbuild（in-tree）与 Makefile（LKM 独立构建），
# in-tree 走 Kbuild，集成方式与官方 setup.sh 同构。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/ksu_zip_prefix.sh
. "${ROOT}/scripts/lib/ksu_zip_prefix.sh"

KERNEL_ROOT="${ROOT}/gki/common"
KSU="${KERNEL_ROOT}/KernelSU"
KSU_REPO="${KSU_REPO:-https://github.com/tiann/KernelSU.git}"
KSU_TAG="${KSU_TAG:-}"
KSU_COMMIT="${KSU_COMMIT:-}"
SUSFS_DIR="${ROOT}/third_party/susfs4ksu"
SUSFS_BRANCH="gki-android15-6.6"
GKI_DEFCONFIG="${KERNEL_ROOT}/arch/arm64/configs/gki_defconfig"

# --- susfs 先行：联动解析要从它的提交史里取 tiann 同步点 ---
# depth=30 覆盖 sync 间隔；手动 pin 旧 commit 时按同一深度取其祖先史。
SUSFS_COMMIT="${SUSFS_COMMIT:-}"
git clone --depth=30 --branch "${SUSFS_BRANCH}" \
  https://github.com/ShirkNeko/susfs4ksu.git "${SUSFS_DIR}"
if [ -n "${SUSFS_COMMIT}" ]; then
  git -C "${SUSFS_DIR}" fetch --depth=30 origin "${SUSFS_COMMIT}"
  git -C "${SUSFS_DIR}" checkout -q --detach FETCH_HEAD
  echo "[+] susfs4ksu manual pin @ $(git -C "${SUSFS_DIR}" rev-parse --short HEAD)"
else
  echo "[+] susfs4ksu HEAD @ $(git -C "${SUSFS_DIR}" rev-parse --short HEAD)"
fi

# --- 解析 KSU ref：手动输入优先，否则联动解析 susfs 最新 sync 点 ---
if [ -n "${KSU_COMMIT}" ]; then
  ref="${KSU_COMMIT}"
  echo "[+] KSU ref: manual commit ${ref}"
elif [ -n "${KSU_TAG}" ]; then
  ref="${KSU_TAG}"
  echo "[+] KSU ref: manual tag ${ref}"
else
  ref="$(git -C "${SUSFS_DIR}" log -30 --format=%B \
    | grep -oE 'tiann/KernelSU/commit/[0-9a-f]{40}' \
    | head -n1 | cut -d/ -f4)"
  if [ -z "${ref}" ]; then
    echo "ERROR: susfs 最近 30 条提交里没有 tiann/KernelSU/commit/<sha> 同步点，" \
         "上游消息格式可能变了。用 ksu_tag / KSU_COMMIT / susfs_commit 手动指定。" >&2
    exit 1
  fi
  echo "[+] KSU ref: linked sync point ${ref} (parsed from susfs log)"
fi

cd "${KERNEL_ROOT}"
if [ ! -d KernelSU ]; then
  if ! git clone --depth=1 --branch "${ref}" "${KSU_REPO}" KernelSU; then
    rm -rf KernelSU
    git clone --filter=blob:none "${KSU_REPO}" KernelSU
  fi
fi
git -C KernelSU fetch --depth=1 origin "${ref}"
git -C KernelSU checkout -q --detach FETCH_HEAD
# 本地重跑时清掉上次 10_/sed/手工改动，保证 patch 总是打在干净源上。
git -C KernelSU reset --hard -q HEAD
if [ -z "${KSU_TAG}" ]; then
  # 联动/commit 模式没有名字：恰为 tag 提交则用 tag 名，否则退回短 SHA。
  KSU_TAG="$(git -C KernelSU describe --tags --exact-match HEAD 2>/dev/null \
    || git -C KernelSU rev-parse --short HEAD)"
fi
ksu_persist_tag

# 10_：驱动侧 SUSFS。susfs4ksu 以官方 KSU 为基准维护，此处应当干净打上；
# 有 hunk 失败即中止（上游漂移需人工对齐，不要带病构建）。
cd "${KSU}"
patch -p1 --no-backup-if-mismatch \
  < "${SUSFS_DIR}/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"

# 10_ 已知 bug（ShirkNeko/susfs4ksu#10 被关未合）：把 selinux_hide.c 里两个
# 运行时解析的函数指针改成 extern 函数，但使用点仍是裸 if (fn) 真值判断，
# GKI 树内 CONFIG_WERROR 下 -Wpointer-bool-conversion 必炸。显式与 NULL 比较。
sed -i \
  -e 's/if (security_dump_masked_av_fn)/if ((void *)security_dump_masked_av_fn != NULL)/' \
  -e 's/if (context_struct_compute_av_fn)/if ((void *)context_struct_compute_av_fn != NULL)/' \
  kernel/feature/selinux_hide.c
cd "${KERNEL_ROOT}"

# 驱动挂进 GKI 树（与官方 setup.sh 同构：相对 symlink + Makefile 追加 + Kconfig endmenu 前）。
DRIVER_DIR="${KERNEL_ROOT}/drivers"
ln -sf "$(realpath --relative-to="${DRIVER_DIR}" "${KSU}/kernel")" "${DRIVER_DIR}/kernelsu"
grep -q "kernelsu" "${DRIVER_DIR}/Makefile" \
  || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "${DRIVER_DIR}/Makefile"
grep -q 'source "drivers/kernelsu/Kconfig"' "${DRIVER_DIR}/Kconfig" \
  || sed -i '/endmenu/i\source "drivers/kernelsu/Kconfig"' "${DRIVER_DIR}/Kconfig"

ksu_rev="$(git -C KernelSU rev-parse --short HEAD)"
echo "[+] KernelSU integrated (${KSU_COMMIT:-${KSU_TAG}} @ ${ksu_rev})"

FRAGMENT="${ROOT}/configs/kernelsu.fragment"
while IFS= read -r line; do
  [[ -z "${line}" || "${line}" =~ ^# ]] && continue
  key="${line%%=*}"
  if grep -qE "^${key}=" "${GKI_DEFCONFIG}"; then
    sed -i "s|^${key}=.*|${line}|" "${GKI_DEFCONFIG}"
  elif grep -qE "^# ${key} is not set" "${GKI_DEFCONFIG}"; then
    sed -i "s|^# ${key} is not set|${line}|" "${GKI_DEFCONFIG}"
  else
    printf '\n%s\n' "${line}" >> "${GKI_DEFCONFIG}"
  fi
done < "${FRAGMENT}"

# 内核侧 SUSFS：fs/ 与 include/linux/ 直接覆盖，50_ 打 GKI 树。
cp -a "${SUSFS_DIR}/kernel_patches/fs/." "${KERNEL_ROOT}/fs/"
cp -a "${SUSFS_DIR}/kernel_patches/include/linux/." "${KERNEL_ROOT}/include/linux/"

cd "${KERNEL_ROOT}"
patch -p1 --forward --fuzz=3 \
  < "${SUSFS_DIR}/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch"

# 10_ Kconfig 菜单与 SukiSU builtin 同名同构（默认全 y）；显式写出防上游默认漂移。
# 取值对齐已验证的 builtin 配置（SUS_PATH=n、SUS_SU 无此键勿加）。
# 官方 Kconfig 无 KSU_MANUAL_SU / KSU_FEATURE_ADBROOT，不要写。
cat >> "${GKI_DEFCONFIG}" <<'EOF'

# === SUSFS (官方 KernelSU + 10_ Kconfig) ===
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=n
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG_TMPFS_XATTR=y
CONFIG_TMPFS_POSIX_ACL=y
EOF
