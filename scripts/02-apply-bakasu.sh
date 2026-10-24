#!/usr/bin/env bash
set -euo pipefail

# BakaSU（ReSukiSU，官方 v3.x 架构 + 原生 SUSFS 菜单）in-tree 集成 + SUSFS + Droidspaces。
#
# 关键配对事实（2026-10-24 预检 + dry-run 实证）：
# - BakaSU 原生自带 KSU_SUSFS Kconfig 菜单 → 不需要 susfs 的 10_ 驱动侧补丁。
# - BakaSU main 自 10-10 封禁 susfs 构建（susfs_compat.mk 无条件 error），默认用
#   sync-susfs 分支（解封现场，驱动已适配现行 susfs API）。
# - susfs 50_ 用**现行 HEAD**：其 selinuxfs.c 不再引用 _with_policy（bd7d199a 旧
#   版引用、定义在 10_ 驱动侧，BakaSU 不打 10_ 必链接炸——run #74 实证）；对 r15
#   树 dry-run 0 失败。其 preinit 依赖（BakaSU 基座无官方 preinit API）用 50_
#   自带的 KSU_NO_PREINIT 宏整体禁用：符号盘点 23 个 ksu_* 中仅 5 个 preinit 系
#   缺失且全部位于该宏守卫内。
# - Droidspaces：SYSVIPC 系移动 task_struct ABI（sysvsem/sysvshm），vendor 模块
#   CRC 失配 → bootloop（K90 真机 6 轮二分实证）。kABI 补丁把两字段挪进
#   ANDROID_KABI 预留位 6/7+8，布局不变。CFS_BANDWIDTH/CGROUP_PIDS 无补丁可救，
#   永久禁用。
#
# 覆盖输入：KSU_TAG/KSU_COMMIT（BakaSU tag/commit）、SUSFS_COMMIT（susfs pin）。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_ROOT="${ROOT}/gki/common"
KSU="${KERNEL_ROOT}/KernelSU"
KSU_REPO="${KSU_REPO:-https://github.com/Baka-SU/BakaSU.git}"
KSU_TAG="${KSU_TAG:-}"
KSU_COMMIT="${KSU_COMMIT:-}"
SUSFS_DIR="${ROOT}/third_party/susfs4ksu"
SUSFS_BRANCH="gki-android15-6.6"
# 默认跟随现行 HEAD（与 sync-susfs 驱动配套，见文件头）；要复现旧组合时覆盖。
SUSFS_COMMIT="${SUSFS_COMMIT:-}"
GKI_DEFCONFIG="${KERNEL_ROOT}/arch/arm64/configs/gki_defconfig"

if [ -n "${KSU_COMMIT}" ]; then
  ref="${KSU_COMMIT}"
elif [ -n "${KSU_TAG}" ]; then
  ref="${KSU_TAG}"
else
  # main 在 2026-10-10 被作者封禁 susfs 构建（susfs_compat.mk 无条件 error，
  # "suspend susfs build"，等 simonpunk 同步官方 preinit）；sync-susfs 是解封
  # 现场（无 error，10-19 活跃）。
  ref="sync-susfs"
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
git -C KernelSU reset --hard -q HEAD
KSU_SHA="$(git -C KernelSU rev-parse --short HEAD)"
echo "[+] BakaSU integrated (${ref} @ ${KSU_SHA})"

# susfs 内核侧（50_ + fs/include），默认跟随 HEAD（与 sync-susfs 驱动配套）。
git clone --depth=1 --branch "${SUSFS_BRANCH}" \
  https://github.com/ShirkNeko/susfs4ksu.git "${SUSFS_DIR}"
if [ -n "${SUSFS_COMMIT}" ]; then
  git -C "${SUSFS_DIR}" fetch --depth=1 origin "${SUSFS_COMMIT}"
  git -C "${SUSFS_DIR}" checkout -q --detach FETCH_HEAD
fi
echo "[+] susfs4ksu @ $(git -C "${SUSFS_DIR}" rev-parse --short HEAD)"

# 驱动挂进 GKI 树（官方 setup.sh 同构）。
DRIVER_DIR="${KERNEL_ROOT}/drivers"
ln -sf "$(realpath --relative-to="${DRIVER_DIR}" "${KSU}/kernel")" "${DRIVER_DIR}/kernelsu"
grep -q "kernelsu" "${DRIVER_DIR}/Makefile" \
  || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "${DRIVER_DIR}/Makefile"
grep -q 'source "drivers/kernelsu/Kconfig"' "${DRIVER_DIR}/Kconfig" \
  || sed -i '/endmenu/i\source "drivers/kernelsu/Kconfig"' "${DRIVER_DIR}/Kconfig"

# kleaf 沙箱物化源树时 bazel 会剔除 .git，BakaSU Kbuild 的守卫与版本自举
# （rev-list count）依赖驱动目录旁的 .git，沙箱内必炸（run #72 实证）。
# 按其 Kbuild 内注释给 bazel 的指引：KSU_SRC 钉到真实 clone 的绝对路径
# （02 与 04 同一次构建内路径一致，本地/CI 通用）。上游改掉该行则 sed
# 不命中，沙箱守卫 fail loud。
sed -i "s|^KSU_SRC := .*|KSU_SRC := ${KSU}/kernel|" "${KSU}/kernel/Kbuild"

# Droidspaces fragment → defconfig。
FRAGMENT="${ROOT}/configs/bakasu.fragment"
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

# 内核侧 SUSFS：fs/include 覆盖 + 50_（干净打上，失败即中止——预检 0 失败）。
cp -a "${SUSFS_DIR}/kernel_patches/fs/." "${KERNEL_ROOT}/fs/"
cp -a "${SUSFS_DIR}/kernel_patches/include/linux/." "${KERNEL_ROOT}/include/linux/"

# 现行 50_ 的 exec.c preinit 依赖（BakaSU 基座无官方 preinit API）用 50_ 自带
# 的兼容宏整体禁用；exec.c include 的 susfs_def.h 是该宏的精确注入点
# （符号盘点：50_ 引用的 23 个 ksu_* 中仅 5 个 preinit 系缺失，全在宏守卫内）。
# BakaSU sync-upstream 带入 preinit 后移除本注入。
sed -i '1i /* BakaSU: no official preinit API yet; disable 50_ preinit path (see 02). */\n#define KSU_NO_PREINIT\n' \
  "${KERNEL_ROOT}/include/linux/susfs_def.h"

cd "${KERNEL_ROOT}"
# --fuzz=3：base.c 等文件的 hunk 需要模糊匹配（kernelsu-official run #44/#64 同参数实证）。
patch -p1 --forward --fuzz=3 --no-backup-if-mismatch \
  < "${SUSFS_DIR}/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch"

# 现行 50_ 的 selinuxfs.c extern 引用全局 my_write_context/my_write_access
# （内核侧 SEL_CONTEXT/SEL_ACCESS 钩子的实现），BakaSU 驱动在 selinux_hide.c
# 里已有完整实现但标记为 static（run #75 链接实证）——把两处定义去 static
# 即按 50_ 预期导出，驱动内部调用不受影响。上游把定义改全局/改接口后此 sed
# 不再命中（前者自然失效，后者 fail loud）。
sed -i \
  -e 's/^static ssize_t my_write_context(struct file \*file/ssize_t my_write_context(struct file *file/' \
  -e 's/^static ssize_t my_write_access(struct file \*file/ssize_t my_write_access(struct file *file/' \
  "${KSU}/kernel/feature/selinux_hide.c"
grep -q '^ssize_t my_write_context' "${KSU}/kernel/feature/selinux_hide.c" \
  || { echo "ERROR: my_write export sed did not apply to selinux_hide.c" >&2; exit 1; }
echo "[+] selinux_hide.c my_write_* exported (grep verified)"

# Droidspaces kABI 补丁（打在 GKI 树 sched.h；上下文 = AOSP r15 原味）。
patch -p1 --forward --no-backup-if-mismatch \
  < "${ROOT}/configs/sysvipc-kabi-6_7_8.patch"

# SUSFS 菜单：BakaSU 原生（10 项，键名与 SukiSU builtin 同构）。
# 取值沿用 K90 真机验证过的组合（SUS_PATH=n）。官方 Kconfig 无
# MANUAL_SU/ADBROOT，不要写。
cat >> "${GKI_DEFCONFIG}" <<'EOF'

# === SUSFS (BakaSU 原生菜单) ===
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
